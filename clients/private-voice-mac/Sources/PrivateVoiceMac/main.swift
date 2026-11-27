import Foundation
import VoicePolicy

#if os(macOS)
import AppKit
import Darwin
import PinnedAudio

private struct PilotError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct NotificationEvent: Codable {
    let id: UUID
    let source: String
    let createdAt: TimeInterval
    let expiresAt: TimeInterval
    let pcm: Data?
}

private func uid(_ snapshot: inout VCOutput) -> String {
    withUnsafeBytes(of: &snapshot.uid) { bytes in
        let prefix = bytes.prefix { $0 != 0 }
        return String(decoding: prefix, as: UTF8.self)
    }
}

private func readOutput(headset: String) -> VCOutput? {
    var snapshot = VCOutput()
    return headset.withCString { vc_read_output($0, &snapshot) } ? snapshot : nil
}

private func boundedRead(_ url: URL, max: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: max + 1) ?? Data()
    guard !bytes.isEmpty, bytes.count <= max else { throw PilotError("invalid file size") }
    return bytes
}

private func privateDirectory(_ rawPath: String) throws -> URL {
    let url = URL(fileURLWithPath: rawPath, isDirectory: true)
    guard mkdir(url.path, 0o700) == 0 || errno == EEXIST else {
        throw PilotError("could not create inbox")
    }
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_uid == getuid(),
          info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_mode & 0o077 == 0 else {
        throw PilotError("inbox must be a private directory owned by the current user")
    }
    return url
}

private func log(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

private let maxPCM = 960_000

private func submit(_ args: [String]) throws {
    guard args.count == 5, let id = UUID(uuidString: args[2]),
          !args[3].isEmpty, args[3].utf8.count <= 100 else {
        throw PilotError("usage: submit INBOX UUID SOURCE {PCM_FILE|--tone}")
    }
    let directory = try privateDirectory(args[1])
    let pcm: Data? = try args[4] == "--tone" ? nil : boundedRead(URL(fileURLWithPath: args[4]), max: maxPCM)
    guard (pcm?.count ?? 0).isMultiple(of: 2) else { throw PilotError("expected 16-bit mono PCM") }
    let now = Date().timeIntervalSince1970
    let notification = NotificationEvent(id: id, source: args[3], createdAt: now, expiresAt: now + 10, pcm: pcm)
    let name = "\(id.uuidString)-\(UUID().uuidString).event"
    try JSONEncoder().encode(notification).write(to: directory.appendingPathComponent(name), options: .atomic)
    log("submitted \(id.uuidString)")
}

private final class Pilot {
    private let inbox: URL
    private let headset: String
    private let speakers: (String, UInt32)?
    private let forceTest: Bool
    private let dryRun: Bool
    private let meetingMonitor: MeetingMonitor
    private var lastMeeting: VoicePolicy.MeetingState?
    private var policy = VoicePolicy()
    private var snapshot: VCOutput?
    private var lastPresence: Bool?
    private var notBefore = Date().timeIntervalSince1970
    private var timer: DispatchSourceTimer?
    private var ownerInput: DispatchSourceRead?
    private var timerFast = false
    private var playback: (OpaquePointer?, VoicePolicy.Delivery, UUID, Double, Double)?
    private var nextScan: Double = 0
    private var observers: [NSObjectProtocol] = []

    init(inbox: URL, headset: String, speakers: (String, UInt32)?, forceTest: Bool, dryRun: Bool,
         obsProbe: String?) {
        self.inbox = inbox
        self.headset = headset
        self.speakers = speakers
        self.forceTest = forceTest
        self.dryRun = dryRun
        meetingMonitor = MeetingMonitor(obsProbe: obsProbe)
    }

    private var uptime: Double { ProcessInfo.processInfo.systemUptime }

    private func refreshOutput() {
        let current = readOutput(headset: headset)
        let route: OutputRoute? = current.flatMap { value in
            var value = value
            let id = uid(&value)
            let kind: OutputRoute.Kind
            if id == headset && vc_bluetooth_transport(value.transport) {
                kind = .headphones
            } else if let (speakerID, source) = speakers, id == speakerID,
                      value.transport == vc_builtin_transport(), value.has_source, value.source == source {
                kind = .speakers
            } else if value.transport == vc_builtin_transport() {
                kind = .cueOnly
            } else {
                return nil
            }
            return OutputRoute(id: id, device: value.device, source: value.has_source ? value.source : nil, kind: kind)
        }
        let present = current?.known_headphones_connected ?? true
        if route != policy.output || present != lastPresence {
            notBefore = Date().timeIntervalSince1970
            switch route?.kind {
            case .headphones: log("route headphones")
            case .speakers: log("route speakers")
            case .cueOnly: log("route cue_only")
            case nil: log("route unavailable")
            }
        }
        lastPresence = present
        policy.updateOutput(route, headphonesConnected: present)
        snapshot = current
    }

    private func finish(_ result: String) {
        guard let (handle, _, id, _, _) = playback else { return }
        playback = nil
        if let handle { vc_stop(handle) }
        log("\(result) \(id.uuidString)")
    }

    private func refreshMeeting(acknowledgeIdleTalk: Bool = false) {
        let state = meetingMonitor.state(acknowledgeIdleTalk: acknowledgeIdleTalk)
        guard lastMeeting != state else { return }
        lastMeeting = state
        notBefore = Date().timeIntervalSince1970
        policy.updateMeeting(state)
        log("meeting \(state)")
        if state != .clear { finish("interrupted_meeting") }
    }

    private func changeMode(_ paused: Bool) {
        notBefore = Date().timeIntervalSince1970
        policy.invalidateOutput()
        policy.setPaused(paused)
        finish("interrupted")
    }

    private func ownerCommand(_ command: String) {
        refreshOutput()
        if command != "resume" { refreshMeeting() }
        let now = uptime
        switch command {
        case "force":
            log(forceTest && policy.enableSpeaker(now: now) ? "force active for synthetic tone" : "force unavailable")
        case "interact": policy.ownerInteraction(now: now)
        case "off":
            policy.invalidateOutput()
            finish("interrupted")
        case "pause": changeMode(true)
        case "resume":
            refreshMeeting(acknowledgeIdleTalk: true)
            changeMode(false)
            log(lastMeeting == .clear ? "resumed" : "resume_pending_meeting")
        case "quit":
            finish("interrupted")
            exit(0)
        default: log("commands: pause, resume, force, interact, off, quit")
        }
    }

    private func samples(for event: NotificationEvent, delivery: VoicePolicy.Delivery) -> [Int16]? {
        if delivery.content == .cue { return tone(count: 1_920, level: 280) }
        if let pcm = event.pcm {
            guard delivery.output.kind == .headphones, (2...maxPCM).contains(pcm.count),
                  pcm.count.isMultiple(of: 2) else { return nil }
            // Data alignment is not guaranteed. Array provides aligned native PCM storage.
            var output = [Int16](repeating: 0, count: pcm.count / 2)
            _ = output.withUnsafeMutableBytes { pcm.copyBytes(to: $0) }
            return output
        }
        return tone(count: 9_600, level: 900)
    }

    private func tone(count: Int, level: Double) -> [Int16] {
        (0..<count).map { i in
            let ramp = min(1.0, Double(i) / 160, Double(count - i - 1) / 160)
            return Int16(level * ramp * sin(2 * .pi * 620 * Double(i) / 16_000))
        }
    }

    private func accept(_ event: NotificationEvent) {
        guard (1...100).contains(event.source.utf8.count) else {
            log("invalid_source")
            return
        }
        let wall = Date().timeIntervalSince1970
        let now = uptime
        let origin = wall - now
        let message = VoiceEvent(id: event.id.uuidString, createdAt: event.createdAt - origin,
                                 expiresAt: event.expiresAt - origin)
        let decision = policy.receive(message, now: now, playing: playback != nil,
                                      notBefore: notBefore - origin)
        guard case .play(let choice) = decision else {
            if case .skipped(let reason) = decision { log("skipped_\(reason.rawValue) \(event.id)") }
            return
        }
        guard let samples = samples(for: event, delivery: choice) else {
            log("skipped_protected \(event.id)")
            return
        }
        refreshOutput()
        refreshMeeting()
        guard var snapshot, policy.canStart(choice, now: uptime) else {
            log("skipped_route_changed \(event.id)")
            return
        }
        let result = choice.content == .cue ? "cue" : "speech"
        let duration = Double(samples.count) / 16_000
        if dryRun {
            let end = uptime + duration
            playback = (nil, choice, event.id, end, end)
            log("would_play_\(result) \(event.id)")
            return
        }
        var error: Int32 = 0
        let handle = headset.withCString { headset in
            samples.withUnsafeBufferPointer {
                vc_play(&snapshot, headset, $0.baseAddress, $0.count, &error)
            }
        }
        guard let handle else {
            log("audio_error \(event.id) \(error)")
            return
        }
        let start = uptime
        playback = (handle, choice, event.id, start + duration, start + duration + 2)
        log("playing_\(result) \(event.id)")
    }

    private func scan() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: inbox.path) else { return }
        // One active output at a time. Busy notifications are consumed, never queued for playback.
        for name in names.sorted() where name.hasSuffix(".event") {
            let file = inbox.appendingPathComponent(name)
            var info = stat()
            guard lstat(file.path, &info) == 0, info.st_uid == getuid(),
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { continue }
            do {
                let bytes = try boundedRead(file, max: 1_310_000)
                try FileManager.default.removeItem(at: file)
                accept(try JSONDecoder().decode(NotificationEvent.self, from: bytes))
            } catch {
                log("invalid_event")
                // Inbox files are disposable notifications. The original remains in its chat.
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func tick() {
        refreshOutput()
        refreshMeeting()
        let now = uptime
        if let (handle, delivery, _, earliestEnd, hardEnd) = playback {
            if !policy.canContinue(delivery, now: now) || handle.map(vc_matches) == false {
                finish("interrupted")
            } else if now >= earliestEnd, handle.map(vc_finished) ?? true {
                finish(handle == nil ? "simulated_end" : delivery.content == .cue ? "cue_played" : "played")
            } else if now >= hardEnd {
                finish("audio_timeout")
            }
        }
        if now >= nextScan {
            scan()
            nextScan = now + 0.2
        }
        let fast = playback != nil
        if fast != timerFast {
            timerFast = fast
            timer?.schedule(deadline: .now(), repeating: .milliseconds(fast ? 25 : 160), leeway: .milliseconds(5))
        }
    }

    func run() -> Never {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.changeMode(true)
            })
        }
        // Local TTY only. Published events do not carry owner commands.
        if isatty(STDIN_FILENO) == 1 {
            let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
            input.setEventHandler { [weak self] in
                guard let line = readLine() else { exit(0) }
                self?.ownerCommand(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            ownerInput = input
            input.resume()
        }
        startTimer()
    }

    private func startTimer() -> Never {
        refreshOutput()
        refreshMeeting()
        log("ready")
        let timer = DispatchSource.makeTimerSource(queue: .main)
        self.timer = timer
        timer.setEventHandler { [self] in tick() }
        timer.schedule(deadline: .now(), repeating: .milliseconds(160), leeway: .milliseconds(5))
        timer.resume()
        dispatchMain()
    }
}

private func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "route":
        guard args.count == 1, var current = readOutput(headset: "") else { throw PilotError("output unavailable") }
        log("uid=\(uid(&current)) bluetooth=\(vc_bluetooth_transport(current.transport)) built_in=\(current.transport == vc_builtin_transport()) source=\(current.has_source ? String(current.source) : "unknown")")
    case "submit":
        try submit(args)
    case "listen":
        guard args.count >= 3, !args[2].isEmpty else {
            throw PilotError("usage: listen INBOX HEADSET_UID [SPEAKER_UID SPEAKER_SOURCE] [--dry-run] [--force-test] [--obs-probe=PATH]")
        }
        let flags = Set(args.dropFirst(3).filter { $0.hasPrefix("--") })
        let positional = args.dropFirst(3).filter { !$0.hasPrefix("--") }
        let speaker: (String, UInt32)?
        if positional.isEmpty {
            speaker = nil
        } else if positional.count == 2, let source = UInt32(positional[1]), !positional[0].isEmpty {
            speaker = (positional[0], source)
        } else {
            throw PilotError("expected speaker UID and numeric data source")
        }
        let probeFlags = flags.filter { $0.hasPrefix("--obs-probe=") }
        guard probeFlags.count <= 1, flags.subtracting(probeFlags).isSubset(of: ["--dry-run", "--force-test"]) else {
            throw PilotError("unknown or duplicate flag")
        }
        let obsProbe = probeFlags.first.map { String($0.dropFirst("--obs-probe=".count)) }
        if let obsProbe, !obsProbe.hasPrefix("/") { throw PilotError("OBS probe needs an absolute path") }
        let directory = try privateDirectory(args[1])
        let lock = open(directory.appendingPathComponent(".listener.lock").path,
                        O_CREAT | O_NOFOLLOW | O_RDWR, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw PilotError("inbox already in use") }
        Pilot(inbox: directory, headset: args[2], speakers: speaker,
              forceTest: flags.contains("--force-test"), dryRun: flags.contains("--dry-run"),
              obsProbe: obsProbe).run()
    default:
        throw PilotError("commands: route, listen, submit")
    }
}

umask(0o077)
do {
    try main()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
#else
print("Private audio playback requires macOS.")
#endif
