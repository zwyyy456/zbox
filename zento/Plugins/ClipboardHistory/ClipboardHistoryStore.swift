import CryptoKit
import Foundation
import SwiftData

@Model
final class ClipboardRecord {
    @Attribute(.unique) var id: UUID
    var kind: String
    var text: String
    @Attribute(.externalStorage) var data: Data
    var digest: String
    var sourceBundleID: String?
    var copiedAt: Date
    var pinned: Bool
    var byteCount: Int

    init(_ payload: ClipboardPayload, at date: Date) {
        id = UUID()
        kind = payload.kind
        text = payload.text
        data = payload.data
        digest = SHA256.hash(data: payload.data).description
        sourceBundleID = payload.sourceBundleID
        copiedAt = date
        pinned = false
        byteCount = payload.data.count
    }
}

nonisolated struct ClipboardEntry: Identifiable, Sendable {
    let id: UUID
    let kind: String
    let text: String
    let sourceBundleID: String?
    let copiedAt: Date
    let pinned: Bool
    let byteCount: Int
}

@MainActor
final class ClipboardHistoryStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false, url: URL? = nil) throws {
        let schema = Schema([ClipboardRecord.self])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration("ClipboardHistory", schema: schema,
                                               isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: configuration)
        context.autosaveEnabled = false
    }

    func entries() throws -> [ClipboardEntry] {
        try records().map {
            ClipboardEntry(id: $0.id, kind: $0.kind, text: $0.text,
                           sourceBundleID: $0.sourceBundleID, copiedAt: $0.copiedAt,
                           pinned: $0.pinned, byteCount: $0.byteCount)
        }
    }

    func add(_ payload: ClipboardPayload, at date: Date = .now) throws {
        let digest = SHA256.hash(data: payload.data).description
        let kind = payload.kind
        let descriptor = FetchDescriptor<ClipboardRecord>(predicate: #Predicate { $0.digest == digest && $0.kind == kind })
        if let existing = try context.fetch(descriptor).first {
            existing.copiedAt = date
            existing.sourceBundleID = payload.sourceBundleID
        } else {
            let all = try records()
            var count = all.count
            var bytes = all.reduce(0) { $0 + $1.byteCount }
            var victims: [ClipboardRecord] = []
            for record in all.reversed() where !record.pinned {
                guard count >= 500 || bytes + payload.data.count > 100 * 1_024 * 1_024 else { break }
                victims.append(record)
                count -= 1
                bytes -= record.byteCount
            }
            guard count < 500, bytes + payload.data.count <= 100 * 1_024 * 1_024 else {
                throw ClipboardHistoryError.storageFull
            }
            for record in victims { context.delete(record) }
            context.insert(ClipboardRecord(payload, at: date))
        }
        try save()
    }

    func payload(for id: UUID) throws -> ClipboardPayload? {
        guard let record = try record(id) else { return nil }
        return ClipboardPayload(kind: record.kind, text: record.text, data: record.data,
                                sourceBundleID: record.sourceBundleID)
    }

    func setPinned(_ pinned: Bool, for id: UUID) throws {
        if let item = try record(id) { item.pinned = pinned }
        try save()
    }

    func prune(days: Int, now: Date = .now) throws {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let expired = try context.fetch(FetchDescriptor<ClipboardRecord>(predicate: #Predicate {
            !$0.pinned && $0.copiedAt < cutoff
        }))
        guard !expired.isEmpty else { return }
        for item in expired { context.delete(item) }
        try save()
    }

    func delete(_ id: UUID) throws {
        if let item = try record(id) { context.delete(item) }
        try save()
    }

    func clear() throws {
        for record in try records() { context.delete(record) }
        try save()
    }

    private func record(_ id: UUID) throws -> ClipboardRecord? {
        try context.fetch(FetchDescriptor<ClipboardRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func records() throws -> [ClipboardRecord] {
        try context.fetch(FetchDescriptor<ClipboardRecord>(sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]))
    }

    private func save() throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}
