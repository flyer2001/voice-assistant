import Cocoa

/// Global hotkey via CGEventTap. Requires Accessibility permission
/// (System Settings > Privacy & Security > Accessibility).
/// keyDown/keyUp callbacks fire on main queue.
final class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private let keyCode: Int64
    private let onDown: () -> Void
    private let onUp: () -> Void
    private var isDown = false

    init(keyCode: UInt16, onDown: @escaping () -> Void, onUp: @escaping () -> Void) {
        self.keyCode = Int64(keyCode)
        self.onDown = onDown
        self.onUp = onUp
    }

    @discardableResult
    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let mon = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                guard code == mon.keyCode else { return Unmanaged.passUnretained(event) }
                switch type {
                case .keyDown:
                    // Auto-repeat suppression: fire onDown only on first press.
                    if !mon.isDown {
                        mon.isDown = true
                        DispatchQueue.main.async { mon.onDown() }
                    }
                    return nil
                case .keyUp:
                    mon.isDown = false
                    DispatchQueue.main.async { mon.onUp() }
                    return nil
                default:
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        return true
    }
}
