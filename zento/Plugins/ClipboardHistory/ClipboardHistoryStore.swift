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
    var fileURLs: [URL] = []

    var title: String {
        kind == "files" ? fileURLs.map(\.lastPathComponent).joined(separator: ", ") : text
    }
}

@MainActor
final class ClipboardHistoryStore {
    private(set) var totalBytes = 0
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
        try updateUsage()
    }

    func entries(query: String = "", filter: ClipboardHistoryFilter = .all,
                 offset: Int = 0, limit: Int = 100) throws -> [ClipboardEntry] {
        let all = filter == .all
        let text = filter == .text
        let links = filter == .links
        let images = filter == .images
        let pinned = filter == .pinned
        let files = filter == .files
        var descriptor = FetchDescriptor<ClipboardRecord>(predicate: #Predicate {
            (query.isEmpty || $0.text.localizedStandardContains(query)) &&
            (all || (text && $0.kind == "text") || (links && $0.kind == "link") ||
             (images && ($0.kind == "png" || $0.kind == "tiff")) || (files && $0.kind == "files") || (pinned && $0.pinned))
        }, sortBy: [SortDescriptor(\.copiedAt, order: .reverse), SortDescriptor(\.id)])
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map {
            ClipboardEntry(id: $0.id, kind: $0.kind, text: $0.text,
                           sourceBundleID: $0.sourceBundleID, copiedAt: $0.copiedAt,
                           pinned: $0.pinned, byteCount: $0.byteCount,
                           fileURLs: $0.kind == "files" ? try ClipboardFileReferences.decode($0.data) : [])
        }
    }

    func add(_ payload: ClipboardPayload, at date: Date = .now, byteLimit: Int = 0) throws {
        let digest = SHA256.hash(data: payload.data).description
        let kind = payload.kind
        let descriptor = FetchDescriptor<ClipboardRecord>(predicate: #Predicate { $0.digest == digest && $0.kind == kind })
        var byteChange = 0
        if let existing = try context.fetch(descriptor).first {
            existing.copiedAt = date
            existing.sourceBundleID = payload.sourceBundleID
        } else {
            let victims = try evictionCandidates(reserving: payload.data.count, limit: byteLimit)
            byteChange = payload.data.count - victims.reduce(0) { $0 + $1.byteCount }
            for record in victims { context.delete(record) }
            context.insert(ClipboardRecord(payload, at: date))
        }
        try save()
        totalBytes += byteChange
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
        guard days > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var descriptor = FetchDescriptor<ClipboardRecord>(predicate: #Predicate {
            !$0.pinned && $0.copiedAt < cutoff
        })
        descriptor.fetchLimit = 200
        while true {
            let expired = try context.fetch(descriptor)
            guard !expired.isEmpty else { return }
            let bytes = expired.reduce(0) { $0 + $1.byteCount }
            for item in expired { context.delete(item) }
            try save()
            totalBytes -= bytes
        }
    }

    func delete(_ id: UUID) throws {
        guard let item = try record(id) else { return }
        let bytes = item.byteCount
        context.delete(item)
        try save()
        totalBytes -= bytes
    }

    func clear() throws {
        try context.delete(model: ClipboardRecord.self)
        try save()
        totalBytes = 0
    }

    private func record(_ id: UUID) throws -> ClipboardRecord? {
        try context.fetch(FetchDescriptor<ClipboardRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func applyByteLimit(_ limit: Int) throws {
        let victims = try evictionCandidates(reserving: 0, limit: limit)
        let bytes = victims.reduce(0) { $0 + $1.byteCount }
        for record in victims { context.delete(record) }
        try save()
        totalBytes -= bytes
    }

    private func evictionCandidates(reserving bytes: Int, limit: Int) throws -> [ClipboardRecord] {
        guard limit > 0, totalBytes + bytes > limit else { return [] }
        var remaining = totalBytes + bytes
        var victims: [ClipboardRecord] = []
        var descriptor = FetchDescriptor<ClipboardRecord>(predicate: #Predicate { !$0.pinned },
            sortBy: [SortDescriptor(\.copiedAt), SortDescriptor(\.id)])
        descriptor.fetchLimit = 100
        while remaining > limit {
            descriptor.fetchOffset = victims.count
            let batch = try context.fetch(descriptor)
            guard !batch.isEmpty else { throw ClipboardHistoryError.storageFull }
            for record in batch {
                victims.append(record)
                remaining -= record.byteCount
                if remaining <= limit { break }
            }
        }
        return victims
    }

    private func updateUsage() throws {
        var bytes = 0
        var descriptor = FetchDescriptor<ClipboardRecord>(sortBy: [SortDescriptor(\.id)])
        descriptor.fetchLimit = 200
        while true {
            let batch = try context.fetch(descriptor)
            bytes += batch.reduce(0) { $0 + $1.byteCount }
            if batch.count < 200 { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
        }
        totalBytes = bytes
    }

    private func save() throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}
