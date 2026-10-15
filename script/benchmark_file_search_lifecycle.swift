import Foundation
import Darwin
import CoreServices

@MainActor final class BenchmarkEvents {
    var change = FileIndexChange()
}

actor BenchmarkPhase {
    var value = "scanning"
    func set(_ value: String) { self.value = value }
}

@main struct LifecycleBenchmark {
    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
    static func memory(_ phase: String) {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let read = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, size)
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        print("phase=\(phase) rss_bytes=\(read == size ? info.pti_resident_size : 0) footprint_bytes=\(result == KERN_SUCCESS ? vm.phys_footprint : 0)")
        fflush(stdout)
    }
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        let mode = args[1], folder = URL(fileURLWithPath: args[2])
        let rootFile = folder.appending(path: "root.json")
        if mode == "prepare" {
            let total = Int(args[3])!
            let rootURL = folder.appending(path: "files")
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            for i in 0..<total {
                let parent = rootURL.appending(path: "项目-\(i / 300)")
                if i % 300 == 0 { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
                try Data().write(to: parent.appending(path: "Project报告-\(i).txt"))
            }
            try JSONEncoder().encode(FileSearchRoot.selected(rootURL)).write(to: rootFile)
            print("fixture_files=\(total)")
            return
        }
        let root = try JSONDecoder().decode(FileSearchRoot.self, from: Data(contentsOf: rootFile))
        let store = FileIndexStore(url: folder.appending(path: "index"))
        let clock = ContinuousClock()
        memory("start")
        if mode == "scan" {
            let scanner = FileIndexScanner()
            let journal = try FileIndexWatcher.journalID(for: root)
            _ = try await store.prepare(root, journalID: journal)
            let baseline = FSEventsGetCurrentEventId()
            let start = clock.now
            let phase = BenchmarkPhase()
            let scan = Task {
                let count = try await scanner.scan(root, store: store)
                let scanTime = ms(start.duration(to: clock.now))
                await phase.set("saving")
                let save = clock.now
                try await store.setCursor(baseline, root: root.id, persist: true)
                print("save_ms=\(ms(save.duration(to: clock.now)))")
                await phase.set("ready")
                return (count, scanTime)
            }
            var samples: [String: [Double]] = [:], cancelSamples: [Double] = [], probes: [Double] = []
            var cancelledQueries = 0
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(50))
                let queryPhase = await phase.value
                let queryStart = clock.now
                _ = try await store.search(FileSearchQuery("报告"), roots: [root], sort: .name)
                samples[queryPhase, default: []].append(ms(queryStart.duration(to: clock.now)))
                let query = Task { try await store.search(FileSearchQuery("type:file"), roots: [root], sort: .modified) }
                try await Task.sleep(for: .milliseconds(1))
                let cancel = clock.now
                query.cancel()
                do { _ = try await query.value } catch is CancellationError { cancelledQueries += 1 }
                cancelSamples.append(ms(cancel.duration(to: clock.now)))
                let blocker = Task { try await store.search(FileSearchQuery("type:file"), roots: [root], sort: .modified) }
                try await Task.sleep(for: .milliseconds(1))
                let probe = clock.now
                _ = try await store.cursor(root: root.id)
                probes.append(ms(probe.duration(to: clock.now)))
                blocker.cancel()
                do { _ = try await blocker.value } catch is CancellationError { }
            }
            let (count, scanTime) = try await scan.value
            print("scan_ms=\(scanTime)")
            print("scan_with_queries_ms=\(ms(start.duration(to: clock.now))) records=\(count)")
            samples["store_probe"] = probes
            samples["cancel_join"] = cancelSamples
            for (name, values) in samples.sorted(by: { $0.key < $1.key }) {
                let sorted = values.sorted()
                print("phase_samples=\(name) count=\(values.count) median_ms=\(sorted[sorted.count / 2]) p95_ms=\(sorted[Int(Double(sorted.count - 1) * 0.95)]) max_ms=\(sorted.last!)")
            }
            print("cancelled_queries=\(cancelledQueries) cancel_attempts=20")
            memory("saved")
            let idle = Int(args[3])!
            if idle > 0 {
                try await Task.sleep(for: .seconds(idle)); memory("idle_\(idle)s")
                try await Task.sleep(for: .seconds(idle)); memory("idle_\(idle * 2)s")
            }
        } else {
            let start = clock.now
            _ = try await store.cursor(root: root.id)
            print("process_cold_open_ms=\(ms(start.duration(to: clock.now)))")
            let replay = clock.now
            let journal = try FileIndexWatcher.journalID(for: root)
            guard let cursor = try await store.prepare(root, journalID: journal) else { throw FileSearchError.storage }
            let events = BenchmarkEvents()
            let watcher = try FileIndexWatcher(root: root, since: cursor) { events.change.merge($0) }
            try await watcher.waitForHistory()
            let change = events.change
            try await FileIndexScanner().reconcile(root, change: change, store: store)
            watcher.stop()
            print("history_replay_ms=\(ms(replay.duration(to: clock.now))) changed_directories=\(change.directories.count + change.shallowDirectories.count)")
            let first = clock.now
            _ = try await store.search(FileSearchQuery("报告-9876"), roots: [root], sort: .name)
            print("first_query_ms=\(ms(first.duration(to: clock.now)))")
            memory("queried")
        }
        await store.releaseMemory()
        memory("released")
    }
}
