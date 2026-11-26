import Foundation

public struct OutputRoute: Equatable {
    public enum Kind { case headphones, speakers, cueOnly }
    public let id: String
    public let device: UInt32
    public let source: UInt32?
    public let kind: Kind

    public init(id: String, device: UInt32, source: UInt32?, kind: Kind) {
        self.id = id
        self.device = device
        self.source = source
        self.kind = kind
    }
}

public struct VoiceEvent {
    public let id: String
    public let createdAt: TimeInterval
    public let expiresAt: TimeInterval

    public init(id: String, createdAt: TimeInterval, expiresAt: TimeInterval) {
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct VoicePolicy {
    public struct Delivery: Equatable {
        public enum Content { case speech, cue }
        public let content: Content
        public let output: OutputRoute
        fileprivate let generation: Int
        fileprivate let expiresAt: TimeInterval
    }

    public enum Decision: Equatable {
        public enum Skip: String { case duplicate, stale, paused, busy, unavailable, capacity }
        case play(Delivery)
        case skipped(Skip)

        public var delivery: Delivery? {
            if case let .play(delivery) = self { return delivery }
            return nil
        }
    }

    public static let speakerIdleLimit: TimeInterval = 600
    public static let eventLifetimeLimit: TimeInterval = 60
    public private(set) var output: OutputRoute?
    private var headphonesConnected = false
    private var paused = false
    private var generation = 0
    private var speakerUntil: TimeInterval?
    private var seen: [String: TimeInterval] = [:]

    public init() {}

    public mutating func updateOutput(_ route: OutputRoute?, headphonesConnected: Bool) {
        guard route != output || headphonesConnected != self.headphonesConnected else { return }
        output = route
        self.headphonesConnected = headphonesConnected
        invalidateOutput()
    }

    public mutating func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        invalidateOutput()
    }

    public mutating func invalidateOutput() {
        speakerUntil = nil
        generation += 1
    }

    public mutating func enableSpeaker(now: TimeInterval) -> Bool {
        guard output?.kind == .speakers, !headphonesConnected, !paused else { return false }
        if !speakerAllowed(now: now) { generation += 1 }
        speakerUntil = now + Self.speakerIdleLimit
        return true
    }

    public mutating func ownerInteraction(now: TimeInterval) {
        guard speakerAllowed(now: now) else { return }
        speakerUntil = now + Self.speakerIdleLimit
    }

    public mutating func receive(
        _ event: VoiceEvent, now: TimeInterval, playing: Bool = false,
        notBefore: TimeInterval = -.infinity
    ) -> Decision {
        let lifetime = event.expiresAt - event.createdAt
        guard lifetime > 0, lifetime <= Self.eventLifetimeLimit,
              event.createdAt >= notBefore, event.createdAt <= now, event.expiresAt > now else {
            return .skipped(.stale)
        }
        seen = seen.filter { $0.value > now }
        guard seen[event.id] == nil else { return .skipped(.duplicate) }
        guard seen.count < 4_096 else { return .skipped(.capacity) }
        // Count attempts even when output is blocked. Retries cannot turn a cue into speech.
        seen[event.id] = event.expiresAt + Self.eventLifetimeLimit
        guard !paused else { return .skipped(.paused) }
        guard !playing else { return .skipped(.busy) }
        guard let output else { return .skipped(.unavailable) }
        let content: Delivery.Content = output.kind == .headphones || speakerAllowed(now: now) ? .speech : .cue
        return .play(Delivery(content: content, output: output, generation: generation, expiresAt: event.expiresAt))
    }

    public func canStart(_ delivery: Delivery, now: TimeInterval) -> Bool {
        now < delivery.expiresAt && canContinue(delivery, now: now)
    }

    public func canContinue(_ delivery: Delivery, now: TimeInterval) -> Bool {
        guard !paused, generation == delivery.generation, output == delivery.output else { return false }
        return delivery.content == .cue || delivery.output.kind == .headphones || speakerAllowed(now: now)
    }

    private func speakerAllowed(now: TimeInterval) -> Bool {
        guard let speakerUntil, output?.kind == .speakers, !headphonesConnected else { return false }
        return now < speakerUntil
    }
}
