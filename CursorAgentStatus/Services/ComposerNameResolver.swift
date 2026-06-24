import Foundation
import SQLite3

/// 从 Cursor 全局状态库读取侧边栏 Agent 名称（如「需求文档生成」）
final class ComposerNameResolver {
    static let shared = ComposerNameResolver()

    private static let dbPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")

    private var cache: [String: String] = [:]
    private var lastRefresh = Date.distantPast
    private let refreshInterval: TimeInterval = 2

    private struct HeadersRoot: Decodable {
        let allComposers: [HeaderEntry]?
    }

    private struct HeaderEntry: Decodable {
        let type: String?
        let composerId: String?
        let name: String?
    }

    func name(for conversationId: String) -> String? {
        refreshIfNeeded()
        return cache[conversationId]
    }

    func refreshIfNeeded(force: Bool = false) {
        if !force, Date().timeIntervalSince(lastRefresh) < refreshInterval { return }
        lastRefresh = Date()
        if let loaded = loadNames() {
            cache = loaded
        }
    }

    private func loadNames() -> [String: String]? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(Self.dbPath.path, &db, flags, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = 'composer.composerHeaders';"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cString = sqlite3_column_text(stmt, 0) else {
            return nil
        }

        let jsonString = String(cString: cString)
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONDecoder().decode(HeadersRoot.self, from: data),
              let composers = root.allComposers else {
            return nil
        }

        var names: [String: String] = [:]
        for entry in composers {
            guard entry.type == "head",
                  let id = entry.composerId,
                  let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            names[id] = name
        }
        return names
    }
}
