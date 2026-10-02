import AppKit
import ApplicationServices

struct WorkspaceRestoreResult: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let applicationName: String
    let succeeded: Bool
    let message: String
}

struct WorkspaceDisplayMapping: Identifiable {
    let id = UUID()
    let layout: WorkspaceLayout
    let missing: [WorkspaceEntry]
    let displays: [WorkspaceDisplay]
}

@MainActor
struct WorkspaceRestorer {
    func restore(_ layout: WorkspaceLayout, mapping: [String: String],
                 report: (WorkspaceRestoreResult) -> Void) async throws {
        var successful = Set<String>()
        for entry in layout.entries {
            await Task.yield()
            try Task.checkCancellation()
            guard AXIsProcessTrusted() else { throw AccessibilityWindowError.permissionRequired }
            let targetID = mapping[entry.displayID] ?? entry.displayID
            if targetID.isEmpty {
                report(WorkspaceRestoreResult(bundleID: entry.bundleID, applicationName: entry.applicationName,
                    succeeded: false, message: String(localized: "Skipped: display unavailable")))
                continue
            }
            do {
                let application = try await application(for: entry)
                try Task.checkCancellation()
                let window = try await waitForWindow(in: application)
                try Task.checkCancellation()
                guard AXIsProcessTrusted() else { throw AccessibilityWindowError.permissionRequired }
                guard let display = WorkspaceDisplay.matching(targetID, in: WorkspaceDisplay.current()),
                      let primaryMaxY = NSScreen.screens.first?.frame.maxY else {
                    throw AccessibilityWindowError.noScreen
                }
                let cocoaFrame = WorkspaceGeometry.restored(entry.frame, in: display.visibleFrame)
                let axFrame = WindowGeometry.axRect(fromCocoaRect: cocoaFrame, primaryScreenMaxY: primaryMaxY)
                try AccessibilityWindows.setFrame(axFrame, of: window)
                let actual = try AccessibilityWindows.frame(of: window)
                guard abs(actual.minX - axFrame.minX) <= 2, abs(actual.minY - axFrame.minY) <= 2,
                      abs(actual.width - axFrame.width) <= 2, abs(actual.height - axFrame.height) <= 2 else {
                    throw WorkspaceRestoreError.constrainedWindow
                }
                successful.insert(entry.bundleID)
                report(WorkspaceRestoreResult(bundleID: entry.bundleID, applicationName: entry.applicationName,
                    succeeded: true, message: String(localized: "Restored")))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard AXIsProcessTrusted() else { throw AccessibilityWindowError.permissionRequired }
                report(WorkspaceRestoreResult(bundleID: entry.bundleID, applicationName: entry.applicationName,
                    succeeded: false, message: error.localizedDescription))
            }
        }
        try Task.checkCancellation()
        if let bundleID = layout.foregroundBundleID, successful.contains(bundleID) {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
        }
    }

    private func application(for entry: WorkspaceEntry) async throws -> NSRunningApplication {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleID)
        guard running.count <= 1 else { throw WorkspaceRestoreError.ambiguousApplication }
        if let app = running.first { return app }
        let url: URL
        if Bundle(url: entry.applicationURL)?.bundleIdentifier == entry.bundleID {
            url = entry.applicationURL
        } else if let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) {
            url = installed
        } else {
            throw ApplicationLaunchError.unableToOpen(entry.applicationName)
        }
        return try await ApplicationLauncher().open(at: url, activates: false)
    }

    private func waitForWindow(in application: NSRunningApplication) async throws -> AXUIElement {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while clock.now < deadline {
            try Task.checkCancellation()
            guard AXIsProcessTrusted() else { throw AccessibilityWindowError.permissionRequired }
            guard !application.isTerminated else { throw AccessibilityWindowError.noTargetApplication }
            let app = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 1)
            if let value = AccessibilityWindows.attribute(kAXMainWindowAttribute, of: app),
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                let main = unsafeDowncast(value, to: AXUIElement.self)
                AXUIElementSetMessagingTimeout(main, 1)
                if WorkspaceWindowAccess.exclusion(of: main, pid: application.processIdentifier) == nil { return main }
            }
            let windows = WorkspaceWindowAccess.windows(for: application.processIdentifier)
                .filter { WorkspaceWindowAccess.exclusion(of: $0, pid: application.processIdentifier) == nil }
            if windows.count == 1 { return windows[0] }
            if windows.count > 1 { throw WorkspaceRestoreError.ambiguousWindow }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw WorkspaceRestoreError.windowUnavailable
    }
}

nonisolated enum WorkspaceRestoreError: LocalizedError {
    case ambiguousApplication, ambiguousWindow, windowUnavailable, constrainedWindow, busy
    var errorDescription: String? {
        switch self {
        case .ambiguousApplication: String(localized: "Multiple instances of this application are running.")
        case .ambiguousWindow: String(localized: "Select the application's main window, then try again.")
        case .windowUnavailable: String(localized: "No eligible window appeared within 10 seconds. Open a normal window on this desktop and try again.")
        case .constrainedWindow: String(localized: "The application limited the requested window position or size.")
        case .busy: String(localized: "A workspace is already being restored.")
        }
    }
}
