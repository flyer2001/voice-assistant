#if os(macOS)
import AppKit
import CoreAudio
import Darwin
import Foundation
import VoicePolicy

// All state is accessed on the same main queue as the pilot.
final class MeetingMonitor {
    private let obsProbe: String?
    private var obsPID: pid_t?
    private var obsProcess: Process?
    private var obsPipe: Pipe?
    private var obsBuffer = Data()
    private var obsSample: (VoicePolicy.MeetingState, TimeInterval)?
    private var retryAfter: TimeInterval = 0
    private var acknowledgedTalk: pid_t?

    init(obsProbe: String?) { self.obsProbe = obsProbe }

    func state(acknowledgeIdleTalk: Bool = false) -> VoicePolicy.MeetingState {
        let recording = obsState()
        let talk = talkState(acknowledgeIdleTalk: acknowledgeIdleTalk && recording == .clear)
        if talk == .busy || recording == .busy { return .busy }
        if talk == .unknown || recording == .unknown { return .unknown }
        return .clear
    }

    private func talkState(acknowledgeIdleTalk: Bool) -> VoicePolicy.MeetingState {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "kontur.talk")
        guard let app = apps.first else {
            acknowledgedTalk = nil
            return .clear
        }
        guard apps.count == 1, #available(macOS 15.0, *),
              let audioProcesses = try? AudioHardwareSystem.shared.processes,
              let bundle = app.bundleURL?.standardizedFileURL.path.precomposedStringWithCanonicalMapping else {
            acknowledgedTalk = nil
            return .unknown
        }
        let pid = app.processIdentifier
        let ownAudio = audioProcesses.filter { process in
            guard let audioPID = try? process.pid else { return false }
            if audioPID == pid { return true }
            var path = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(audioPID, &path, UInt32(path.count)) > 0 else { return false }
            return String(cString: path).precomposedStringWithCanonicalMapping.hasPrefix(bundle + "/")
        }
        for process in ownAudio {
            let input = try? process.isRunningInput
            let output = try? process.isRunningOutput
            if input == true || output == true {
                acknowledgedTalk = nil
                return .busy
            }
            if input == nil || output == nil {
                acknowledgedTalk = nil
                return .unknown
            }
        }
        // Silent audio streams alone don't establish that the conference ended.
        if acknowledgeIdleTalk { acknowledgedTalk = pid }
        return acknowledgedTalk == pid ? .clear : .unknown
    }

    private func obsState() -> VoicePolicy.MeetingState {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.obsproject.obs-studio")
        let pid = apps.first?.processIdentifier
        if pid != obsPID {
            detachProbe()
            obsPID = pid
            retryAfter = 0
        }
        guard !apps.isEmpty else { return .clear }
        guard apps.count == 1, let obsProbe else { return .unknown }
        let now = ProcessInfo.processInfo.systemUptime
        if obsProcess == nil && now >= retryAfter { startProbe(obsProbe, now: now) }
        guard let (state, timestamp) = obsSample else { return .unknown }
        let age = Date().timeIntervalSince1970 - timestamp
        return (0...0.8).contains(age) ? state : .unknown
    }

    private func startProbe(_ path: String, now: TimeInterval) {
        retryAfter = now + 2
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [path, "watch-record"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak pipe] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, let pipe, self.obsPipe === pipe else { return }
                if data.isEmpty {
                    self.detachProbe()
                } else {
                    self.consume(data)
                }
            }
        }
        obsPipe = pipe
        obsProcess = process
        do {
            try process.run()
        } catch {
            detachProbe()
        }
    }

    private func detachProbe() {
        obsPipe?.fileHandleForReading.readabilityHandler = nil
        if obsProcess?.isRunning == true { obsProcess?.terminate() }
        obsProcess = nil
        obsPipe = nil
        obsSample = nil
        obsBuffer.removeAll()
    }

    private func consume(_ data: Data) {
        obsBuffer.append(data)
        if obsBuffer.count > 4_096 {
            detachProbe()
            return
        }
        while let newline = obsBuffer.firstIndex(of: 10) {
            let words = String(decoding: obsBuffer.prefix(upTo: newline), as: UTF8.self).split(separator: " ")
            obsBuffer.removeSubrange(...newline)
            guard words.count == 2, let timestamp = Double(words[1]), timestamp.isFinite else {
                obsSample = nil
                continue
            }
            switch words[0] {
            case "recording": obsSample = (.busy, timestamp)
            case "clear": obsSample = (.clear, timestamp)
            default: obsSample = nil
            }
        }
    }
}
#endif
