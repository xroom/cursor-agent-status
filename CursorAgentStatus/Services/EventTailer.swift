import Foundation
import Darwin

final class EventTailer {
    static let statusDirectory = StatusStore.statusDirectory
    static let eventsFile = StatusStore.eventsFile

    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0
    private var pendingBuffer = Data()

    var onEvent: (@Sendable (AgentEvent) -> Void)?

    func start() {
        ensureStatusDirectory()
        ensureEventsFile()
        offset = (try? FileHandle(forReadingFrom: Self.eventsFile).seekToEnd()) ?? 0

        let fd = open(Self.eventsFile.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let queue = DispatchQueue(label: "com.cursor-agent-status.event-tailer")
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.readNewBytes()
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        try? fileHandle?.close()
        fileHandle = nil
    }

    func replayAllEvents() -> [AgentEvent] {
        guard FileManager.default.fileExists(atPath: Self.eventsFile.path),
              let data = try? Data(contentsOf: Self.eventsFile),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> AgentEvent? in
                guard !line.isEmpty else { return nil }
                return decodeEvent(from: Data(line.utf8))
            }
    }

    private func ensureStatusDirectory() {
        try? FileManager.default.createDirectory(at: Self.statusDirectory, withIntermediateDirectories: true)
    }

    private func ensureEventsFile() {
        if !FileManager.default.fileExists(atPath: Self.eventsFile.path) {
            FileManager.default.createFile(atPath: Self.eventsFile.path, contents: nil)
        }
    }

    private func readNewBytes() {
        guard let handle = try? FileHandle(forReadingFrom: Self.eventsFile) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            guard !data.isEmpty else { return }
            offset += UInt64(data.count)
            process(data)
        } catch {
            // File may have been rotated or recreated; reset offset.
            offset = 0
            pendingBuffer.removeAll()
        }
    }

    private func process(_ data: Data) {
        pendingBuffer.append(data)

        while let range = pendingBuffer.firstRange(of: Data([0x0A])) {
            let lineData = pendingBuffer.subdata(in: 0..<range.lowerBound)
            pendingBuffer.removeSubrange(0...range.lowerBound)
            guard !lineData.isEmpty, let event = decodeEvent(from: lineData) else { continue }
            onEvent?(event)
        }
    }

    private func decodeEvent(from data: Data) -> AgentEvent? {
        let decoder = JSONDecoder()
        return try? decoder.decode(AgentEvent.self, from: data)
    }
}

private extension Data {
    func firstRange(of target: Data) -> Range<Int>? {
        guard !target.isEmpty, count >= target.count else { return nil }
        for index in 0...(count - target.count) {
            if subdata(in: index..<(index + target.count)) == target {
                return index..<(index + target.count)
            }
        }
        return nil
    }
}
