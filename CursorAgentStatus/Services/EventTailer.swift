import Foundation
import Darwin

final class EventTailer {
    static let statusDirectory = StatusStore.statusDirectory
    static let eventsFile = StatusStore.eventsFile

    private let queue = DispatchQueue(label: "com.cursor-agent-status.event-tailer", qos: .userInteractive)
    private var readHandle: FileHandle?
    private var watchSource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var offset: UInt64 = 0
    private var pendingBuffer = Data()

    var onEvent: (@Sendable (AgentEvent) -> Void)?

    func start() {
        ensureStatusDirectory()
        ensureEventsFile()
        openReadHandle()
        offset = currentFileSize()

        startFileWatcher()
        startPolling(every: .milliseconds(200))
        queue.async { [weak self] in
            self?.readNewBytes()
        }
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        watchSource?.cancel()
        watchSource = nil
        try? readHandle?.close()
        readHandle = nil
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

    private func openReadHandle() {
        readHandle = try? FileHandle(forReadingFrom: Self.eventsFile)
    }

    private func currentFileSize() -> UInt64 {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: Self.eventsFile.path),
           let size = attrs[.size] as? NSNumber {
            return size.uint64Value
        }
        return 0
    }

    private func startFileWatcher() {
        let fd = open(Self.eventsFile.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.readNewBytes()
        }

        source.setCancelHandler {
            close(fd)
        }

        watchSource = source
        source.resume()
    }

    private func startPolling(every interval: DispatchTimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.readNewBytes()
        }
        pollTimer = timer
        timer.resume()
    }

    private func readNewBytes() {
        let fileSize = currentFileSize()
        if fileSize < offset {
            // File truncated or rotated.
            try? readHandle?.close()
            readHandle = nil
            offset = 0
            pendingBuffer.removeAll()
            openReadHandle()
        }

        guard fileSize > offset else { return }

        if readHandle == nil {
            openReadHandle()
        }
        guard let handle = readHandle else { return }

        do {
            try handle.seek(toOffset: offset)
            let length = Int(fileSize - offset)
            guard length > 0 else { return }
            let data = try handle.read(upToCount: length) ?? Data()
            guard !data.isEmpty else { return }
            offset += UInt64(data.count)
            process(data)
        } catch {
            try? readHandle?.close()
            readHandle = nil
            offset = 0
            pendingBuffer.removeAll()
        }
    }

    private func process(_ data: Data) {
        pendingBuffer.append(data)

        while let newline = pendingBuffer.firstIndex(of: 0x0A) {
            let lineData = pendingBuffer.subdata(in: 0..<newline)
            pendingBuffer.removeSubrange(0...newline)
            guard !lineData.isEmpty, let event = decodeEvent(from: lineData) else { continue }
            onEvent?(event)
        }
    }

    private func decodeEvent(from data: Data) -> AgentEvent? {
        try? JSONDecoder().decode(AgentEvent.self, from: data)
    }
}
