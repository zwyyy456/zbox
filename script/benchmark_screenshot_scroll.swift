// Synthetic pixels only. Compile with ScreenshotScrollStitcher.swift; no screen capture or user data.
import CoreGraphics
import Foundation
import Darwin

nonisolated enum ScreenshotError: Error { case captureFailed, exportFailed }

@main struct ScrollBenchmark {
    struct Memory {
        let rss: UInt64
        let footprint: UInt64
    }
    static func memory() -> Memory {
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
        return Memory(rss: read == size ? info.pti_resident_size : 0,
                      footprint: result == KERN_SUCCESS ? vm.phys_footprint : 0)
    }
    static func report(_ phase: String) {
        let m = memory()
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("phase=\(phase) rss_bytes=\(m.rss) footprint_bytes=\(m.footprint) peak_rss_bytes=\(usage.ru_maxrss)")
        fflush(stdout)
    }
    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
    static func frame(top: Int) throws -> CGImage {
        let w = 2000, h = 1200
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let raw = context.data else { throw ScreenshotError.captureFailed }
        let pixels = raw.assumingMemoryBound(to: UInt32.self)
        for y in 0..<h {
            for x in 0..<w {
                var value = UInt32(truncatingIfNeeded: (y + top) * w + x)
                value = (value ^ (value >> 16)) &* 0x7feb352d
                value = (value ^ (value >> 15)) &* 0x846ca68b
                value ^= value >> 16
                let gray = value & 255
                pixels[y * w + x] = gray | gray << 8 | gray << 16 | 0xff000000
            }
        }
        guard let image = context.makeImage() else { throw ScreenshotError.captureFailed }
        return image
    }
    static func appendFrame(_ engine: ScreenshotScrollStitcher, top: Int) async throws -> ScreenshotScrollStitcher.Update? {
        let image = try autoreleasepool { try frame(top: top) }
        return try await engine.append(image)
    }
    static func run(_ mode: String) async throws {
        var engine: ScreenshotScrollStitcher? = ScreenshotScrollStitcher()
        weak var releasedEngine = engine
        var preview: CGImage?
        let start = ContinuousClock.now
        for top in stride(from: 0, through: 14_800, by: 400) {
            let update = try await appendFrame(engine!, top: top)
            guard let update, update.height == top + 1200 else { throw ScreenshotError.captureFailed }
            preview = update.preview
            if top == 0 { report("first_frame") }
        }
        withExtendedLifetime(preview) { report("full_32mp_strips") }
        print("append_total_ms=\(ms(start.duration(to: .now)))")
        if mode == "finish" {
            let start = ContinuousClock.now
            let result = try await engine!.finish()
            // Exercise the retained output as an editor would; metadata-only reads can
            // let optimized builds end the backing pixels' lifetime before a sample.
            guard let display = CGContext(data: nil, width: 200, height: 1600, bitsPerComponent: 8,
                bytesPerRow: 800, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScreenshotError.exportFailed }
            report("assembled_image")
            display.draw(result, in: CGRect(x: 0, y: 0, width: 200, height: 1600))
            print("output_pixels=\(result.width * result.height)")
            print("finish_ms=\(ms(start.duration(to: .now)))")
        } else {
            let next = try frame(top: 15_200)
            let pending = Task { [worker = engine!] in try await worker.append(next) }
            try await Task.sleep(for: .milliseconds(1))
            let start = ContinuousClock.now
            pending.cancel()
            do {
                _ = try await pending.value
                print("cancel_observed=false")
            } catch is CancellationError { print("cancel_observed=true") }
            print("cancel_ms=\(ms(start.duration(to: .now)))")
        }
        preview = nil
        engine = nil
        print("engine_released=\(releasedEngine == nil)")
    }
    static func main() async throws {
        let mode = CommandLine.arguments.dropFirst().first ?? "finish"
        guard mode == "finish" || mode == "cancel" else { throw ScreenshotError.captureFailed }
        print("mode=\(mode) frame_pixels=2400000 max_output_pixels=32000000")
        report("start")
        let sampler = Task.detached { () -> Memory in
            var rss: UInt64 = 0, footprint: UInt64 = 0
            while !Task.isCancelled {
                let current = memory()
                rss = max(rss, current.rss); footprint = max(footprint, current.footprint)
                try? await Task.sleep(for: .milliseconds(10))
            }
            return Memory(rss: rss, footprint: footprint)
        }
        let cycles = Int(CommandLine.arguments.dropFirst(2).first ?? "1") ?? 1
        guard cycles > 0 else { throw ScreenshotError.captureFailed }
        for cycle in 1...cycles {
            print("cycle=\(cycle)")
            try await run(mode)
            report("released")
            try await Task.sleep(for: .seconds(2)); report("released_2s")
            try await Task.sleep(for: .seconds(8)); report("released_10s")
        }
        sampler.cancel()
        let peak = await sampler.value
        print("sampled_peak_rss_bytes=\(peak.rss) sampled_peak_footprint_bytes=\(peak.footprint)")
    }
}
