import AppKit

/// Tracks physical holds independently from key-repeat and capture task lifetime.
nonisolated struct TextLookupTriggerState {
    var keys: Set<UInt32> = []
    var modifiers: UInt32 = 0
    var pointerHeld = false
    var selectionHeld = false
    var pointerDeadline: TimeInterval?
    var mouseStart: CGPoint?
    var didDrag = false
    var doubleClickQualified = false

    func holds(_ shortcut: TextLookupShortcut) -> Bool {
        modifiers == shortcut.modifiers && keys == Set(shortcut.keyCode.map { [$0] } ?? [])
    }

    mutating func keyboardChanged(configuration: TextLookupTriggers, time: TimeInterval) -> Bool {
        let pointer = configuration.pointerEnabled && holds(configuration.pointerShortcut)
        if pointer && !pointerHeld && mouseStart == nil { pointerDeadline = time + 0.5 }
        if !pointer { pointerDeadline = nil }
        pointerHeld = pointer
        let selection = configuration.dragEnabled && configuration.dragRequiresShortcut && holds(configuration.dragShortcut)
        let triggerSelection = selection && !selectionHeld && mouseStart == nil
        selectionHeld = selection
        return triggerSelection
    }

    mutating func consumePointer(at time: TimeInterval) -> Bool {
        guard let deadline = pointerDeadline, time >= deadline, pointerHeld else { return false }
        pointerDeadline = nil
        return true
    }

    mutating func mouseDown(at point: CGPoint, clickCount: Int, configuration: TextLookupTriggers) {
        pointerDeadline = nil
        mouseStart = point
        didDrag = false
        doubleClickQualified = clickCount == 2 && configuration.doubleClickEnabled
            && (!configuration.doubleClickRequiresShortcut || holds(configuration.doubleClickShortcut))
    }

    mutating func mouseDragged(to point: CGPoint) {
        guard let start = mouseStart else { return }
        if pow(point.x - start.x, 2) + pow(point.y - start.y, 2) >= 16 { didDrag = true }
    }

    mutating func mouseUp(configuration: TextLookupTriggers) -> Bool {
        defer { mouseStart = nil; didDrag = false; doubleClickQualified = false }
        guard mouseStart != nil else { return false }
        if didDrag { return configuration.dragEnabled && !configuration.dragRequiresShortcut }
        return doubleClickQualified && (!configuration.doubleClickRequiresShortcut || holds(configuration.doubleClickShortcut))
    }
}

@MainActor
final class TextLookupTriggerMonitor {
    var onMouseDown: (() -> Void)?
    var onSelection: ((CGPoint, Bool) -> Void)?
    var onPointer: ((CGPoint) -> Void)?
    var ignoresWindow: ((NSWindow?) -> Bool)?
    var configuration = TextLookupTriggers() { didSet { reset() } }
    var isSuspended = false { didSet { reset() } }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyboardTap: CFMachPort?
    private var keyboardSource: CFRunLoopSource?
    private var consumedKeys: Set<UInt16> = []
    private var holdTask: Task<Void, Never>?
    private var state = TextLookupTriggerState()

    func start() throws {
        guard globalMonitor == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let suppress = MainActor.assumeIsolated {
                    let monitor = Unmanaged<TextLookupTriggerMonitor>.fromOpaque(context).takeUnretainedValue()
                    return monitor.handleKeyboard(type: type, event: event)
                }
                return suppress ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw TextLookupTriggerError.keyboardMonitoringUnavailable
        }
        keyboardTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        keyboardSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .leftMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        if let keyboardSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keyboardSource, .commonModes) }
        if let keyboardTap { CFMachPortInvalidate(keyboardTap) }
        keyboardSource = nil
        keyboardTap = nil
        consumedKeys.removeAll()
        reset()
    }

    private func handleKeyboard(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset()
            if let keyboardTap { CGEvent.tapEnable(tap: keyboardTap, enable: true) }
            return false
        }
        guard !isSuspended, let keyEvent = NSEvent(cgEvent: event) else { return false }
        handle(keyEvent)
        if type == .keyUp, consumedKeys.remove(keyEvent.keyCode) != nil { return true }
        if type == .keyDown {
            if consumedKeys.contains(keyEvent.keyCode) { return true }
            if configuration.activeShortcuts.contains(where: { $0.1.keyCode != nil && state.holds($0.1) }) {
                consumedKeys.insert(keyEvent.keyCode)
                return true
            }
        }
        return false
    }

    private func reset() {
        holdTask?.cancel()
        holdTask = nil
        state = TextLookupTriggerState()
        consumedKeys.removeAll()
    }

    private func handle(_ event: NSEvent) {
        guard !isSuspended else { return }
        let flags = event.modifierFlags
        state.modifiers = (flags.contains(.command) ? HotkeyModifiers.command : 0)
            | (flags.contains(.option) ? HotkeyModifiers.option : 0)
            | (flags.contains(.control) ? HotkeyModifiers.control : 0)
            | (flags.contains(.shift) ? HotkeyModifiers.shift : 0)
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            holdTask?.cancel()
            state.pointerDeadline = nil
            if ignoresWindow?(event.window) == true { state.mouseStart = nil; return }
            onMouseDown?()
            if event.type == .leftMouseDown {
                state.mouseDown(at: NSEvent.mouseLocation, clickCount: event.clickCount, configuration: configuration)
            } else { state.mouseStart = nil }
        case .leftMouseDragged:
            state.mouseDragged(to: NSEvent.mouseLocation)
        case .leftMouseUp:
            if state.mouseUp(configuration: configuration) { onSelection?(NSEvent.mouseLocation, false) }
        case .keyDown, .keyUp, .flagsChanged:
            if event.type == .keyDown {
                guard !event.isARepeat else { return }
                state.keys.insert(UInt32(event.keyCode))
            } else if event.type == .keyUp { state.keys.remove(UInt32(event.keyCode)) }
            let now = ProcessInfo.processInfo.systemUptime
            if state.keyboardChanged(configuration: configuration, time: now) {
                onSelection?(NSEvent.mouseLocation, true)
            }
            holdTask?.cancel()
            holdTask = nil
            if let deadline = state.pointerDeadline {
                holdTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(max(0, deadline - now))) } catch { return }
                    guard let self, self.state.consumePointer(at: ProcessInfo.processInfo.systemUptime) else { return }
                    self.onPointer?(NSEvent.mouseLocation)
                }
            }
        default: break
        }
    }
}

private enum TextLookupTriggerError: LocalizedError {
    case keyboardMonitoringUnavailable

    var errorDescription: String? {
        String(localized: "Could not monitor lookup shortcuts. Check Accessibility permission and enable Text Lookup again.")
    }
}
