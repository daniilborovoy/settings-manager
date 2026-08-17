import Foundation
import Observation

/// In-memory log of backend calls, port of lib/logger.ts + api.ts logging.
@MainActor
@Observable
final class LogStore {
    struct Entry: Identifiable {
        let id = UUID()
        let time = Date()
        let command: String
        let args: String?
        let ok: Bool
        let durationMS: Int
        let result: String?
        let error: String?
    }

    private(set) var entries: [Entry] = []

    var errorCount: Int { entries.filter { !$0.ok }.count }

    func add(command: String, args: String?, ok: Bool, durationMS: Int, result: String? = nil, error: String? = nil) {
        entries.insert(
            Entry(command: command, args: args, ok: ok, durationMS: durationMS, result: result, error: error),
            at: 0
        )
        if entries.count > 300 { entries.removeLast() }
    }

    func clear() { entries.removeAll() }
}
