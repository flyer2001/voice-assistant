import SwiftUI
import UIKit

/// Bridges physical-keyboard key events (e.g. from a paired ZMK Bluetooth
/// keyboard) into SwiftUI callbacks. Uses UIResponder.pressesBegan / -Ended
/// so both keyDown and keyUp are observed — needed for hold-to-speak.
///
/// Foreground only — iOS does not deliver hardware-keyboard events to
/// backgrounded apps. System-reserved keys (volume, brightness, Cmd-Tab, etc.)
/// stay consumed by the OS; F13-F19 / regular alphanum are free.
struct KeyMonitor: UIViewControllerRepresentable {
    var onKeyDown: (UIKeyboardHIDUsage) -> Void
    var onKeyUp: (UIKeyboardHIDUsage) -> Void

    func makeUIViewController(context: Context) -> KeyMonitorViewController {
        let vc = KeyMonitorViewController()
        vc.onKeyDown = onKeyDown
        vc.onKeyUp = onKeyUp
        return vc
    }

    func updateUIViewController(_ uiVC: KeyMonitorViewController, context: Context) {
        uiVC.onKeyDown = onKeyDown
        uiVC.onKeyUp = onKeyUp
    }
}

final class KeyMonitorViewController: UIViewController {
    var onKeyDown: ((UIKeyboardHIDUsage) -> Void)?
    var onKeyUp: ((UIKeyboardHIDUsage) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed: Set<UIPress> = []
        for press in presses {
            guard let key = press.key else { continue }
            onKeyDown?(key.keyCode)
            consumed.insert(press)
        }
        let remaining = presses.subtracting(consumed)
        if !remaining.isEmpty {
            super.pressesBegan(remaining, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var consumed: Set<UIPress> = []
        for press in presses {
            guard let key = press.key else { continue }
            onKeyUp?(key.keyCode)
            consumed.insert(press)
        }
        let remaining = presses.subtracting(consumed)
        if !remaining.isEmpty {
            super.pressesEnded(remaining, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key {
                onKeyUp?(key.keyCode)
            }
        }
        super.pressesCancelled(presses, with: event)
    }
}
