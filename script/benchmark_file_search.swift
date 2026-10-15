import Foundation
import Darwin

@main struct Benchmark {
    enum InputError: Error { case expectedPositiveRecordCount }
    static func main() async throws {
        guard let count = Int(CommandLine.arguments.dropFirst().first ?? "100000"), count > 0 else {
            throw InputError.expectedPositiveRecordCount
        }
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = FileSearchRoot(url: URL(fileURLWithPath: "/Synthetic"), volumeID: "test", fileID: 1)
        let store = FileIndexStore(url: folder.appending(path: "index"))
        let mode = CommandLine.arguments.dropFirst(2).first ?? "repeated"
        let distinct = mode == "repeated" ? 10000 : count
        print("dataset=\(mode)")
        let clock = ContinuousClock()
        let build = clock.now
        let generation = UUID()
        for offset in stride(from: 0, to: count, by: 256) {
            let batch = (offset..<min(offset + 256, count)).map { i in
                let name: String
                switch mode {
                case "chinese": name = "年度项目报告-\(i).txt"
                case "mixed": name = "Project项目-\(i)-Report报告.txt"
                default: name = i % distinct == 1 ? "年度报告.txt" : "document-\(i % distinct).txt"
                }
                return IndexedFile(rootID: root.id, path: "dir\(i / 10000)/\(name)", name: name,
                    isDirectory: false, size: Int64(i), modified: Date(timeIntervalSince1970: Double(i)))
            }
            try await store.upsert(batch, generation: generation)
        }
        print("ingest_ms=\(ms(build.duration(to: clock.now)))")
        reportPeak("ingested")
        let save = clock.now
        try await store.setCursor(1, root: root.id)
        print("snapshot_save_ms=\(ms(save.duration(to: clock.now)))")
        reportPeak("saved")
        let snapshotURL = folder.appending(path: "index/" + root.id.uuidString + ".index")
        print("snapshot_bytes=\(try snapshotURL.resourceValues(forKeys: [.fileSizeKey]).fileSize!)")
        print("records=\(count) total_build_ms=\(ms(build.duration(to: clock.now)))")
        let read = FileIndexStore(url: folder.appending(path: "index"))
        let load = clock.now
        _ = try await read.cursor(root: root.id)
        print("load_ms=\(ms(load.duration(to: clock.now)))")
        let queries: [String]
        switch mode {
        case "chinese": queries = ["年度项目报告-9876", "项目报告", "不存在", "年度", "ext:txt path:dir2"]
        case "mixed": queries = ["project项目-9876", "report报告", "不存在", "project", "ext:txt path:dir2"]
        default: queries = ["document-9876", "年度", "does-not-exist", "document", "ext:txt path:dir2"]
        }
        for query in queries {
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = clock.now
                _ = try await read.search(FileSearchQuery(query), roots: [root], sort: .relevance)
                samples.append(ms(start.duration(to: clock.now)))
            }
            samples.sort()
            print("query=\(query) median_ms=\(samples[2]) max_ms=\(samples.last!)")
        }
    }
    static func reportPeak(_ phase: String) {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("phase=\(phase) peak_rss_bytes=\(usage.ru_maxrss)")
    }
    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
