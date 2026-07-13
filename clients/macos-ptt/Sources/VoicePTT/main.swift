import Cocoa
import AVFoundation

final class App: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotkey: HotkeyMonitor!
    let recorder = AudioRecorder()
    var config: Config!
    var startTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            config = try Config.load()
        } catch {
            print("~/.voice-ptt/config.json missing or invalid: \(error)")
            print("Copy config.example.json → ~/.voice-ptt/config.json and fill values.")
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon("🎙️")
        statusItem.menu = buildMenu()

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { print("Microphone permission denied") }
        }

        hotkey = HotkeyMonitor(
            keyCode: config.hotkeyCode,
            onDown: { [weak self] in self?.pttDown() },
            onUp: { [weak self] in self?.pttUp() }
        )
        if !hotkey.start() {
            print("Failed to start hotkey. Grant Accessibility: System Settings > Privacy & Security > Accessibility.")
            setIcon("⚠️A11y")
        }

        print("voice-ptt ready. Hotkey keyCode=\(config.hotkeyCode). Hold to record.")
    }

    func pttDown() {
        guard !recorder.isRecording else { return }
        do {
            try recorder.start()
            startTime = Date()
            setIcon("🔴")
        } catch {
            setIcon("⚠️mic")
            print("Recording failed: \(error)")
        }
    }

    func pttUp() {
        guard let url = recorder.stop() else { return }
        let dur = startTime.map { Date().timeIntervalSince($0) } ?? 0
        setIcon("⏳")
        if dur < 0.3 {
            setIcon("❓")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.setIcon("🎙️") }
            return
        }
        Task { @MainActor in
            do {
                let t0 = Date()
                let result = try await BackendClient(config: config).uploadAudio(fileURL: url)
                let latency = Int(Date().timeIntervalSince(t0) * 1000)
                print("[\(latency)ms] \(result.text)")
                notify(title: "PTT (\(latency)ms)", body: result.text)
                if config.speakReply { speak(result.text) }
            } catch {
                print("Upload failed: \(error)")
                notify(title: "PTT error", body: "\(error)")
            }
            setIcon("🎙️")
        }
    }

    func setIcon(_ s: String) {
        DispatchQueue.main.async { self.statusItem.button?.title = s }
    }

    func speak(_ text: String) {
        let proc = Process()
        proc.launchPath = "/usr/bin/say"
        var args: [String] = []
        if let voice = config.sayVoice { args += ["-v", voice] }
        args.append(text)
        proc.arguments = args
        try? proc.run()
    }

    func notify(title: String, body: String) {
        let script = """
        display notification "\(escape(body))" with title "\(escape(title))"
        """
        let proc = Process()
        proc.launchPath = "/usr/bin/osascript"
        proc.arguments = ["-e", script]
        try? proc.run()
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "voice-ptt (hold F19 to talk)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
