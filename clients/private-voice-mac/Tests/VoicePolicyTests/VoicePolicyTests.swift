import Testing
@testable import VoicePolicy

private let headphones = OutputRoute(id: "headset", device: 8, source: nil, kind: .headphones)
private let speakers = OutputRoute(id: "laptop", device: 10, source: 1, kind: .speakers)

private func event(_ id: String = "report", created: Double = 100, expires: Double = 110) -> VoiceEvent {
    VoiceEvent(id: id, createdAt: created, expiresAt: expires)
}

@Test func headphoneRemovalInvalidatesAudioEvenAfterHeadphonesReturn() throws {
    var policy = VoicePolicy()
    policy.updateOutput(headphones, headphonesConnected: true)
    let delivery = try #require(policy.receive(event(), now: 101).delivery)
    #expect(delivery.content == .speech)
    policy.updateOutput(speakers, headphonesConnected: false)
    #expect(!policy.canContinue(delivery, now: 102))
    policy.updateOutput(headphones, headphonesConnected: true)
    #expect(!policy.canStart(delivery, now: 103))
    #expect(policy.receive(event(), now: 103) == .skipped(.duplicate))
    #expect(policy.receive(event("new", created: 104, expires: 111), now: 104).delivery?.content == .speech)
}

@Test func absentHeadphonesUseACueAndUnknownRoutesStaySilent() throws {
    var policy = VoicePolicy()
    #expect(policy.receive(event(), now: 101) == .skipped(.unavailable))
    policy.updateOutput(speakers, headphonesConnected: false)
    let cue = try #require(policy.receive(event("cue"), now: 101).delivery)
    #expect(cue.content == .cue)
    policy.updateOutput(headphones, headphonesConnected: true)
    #expect(!policy.canContinue(cue, now: 102))
    #expect(policy.receive(event("cue"), now: 103) == .skipped(.duplicate))
}

@Test func forceExpiresDuringPlaybackAndAgentTrafficDoesNotRenewIt() throws {
    var policy = VoicePolicy()
    policy.updateOutput(speakers, headphonesConnected: false)
    let enabled = policy.enableSpeaker(now: 100)
    #expect(enabled)
    let delivery = try #require(policy.receive(event(created: 690, expires: 720), now: 699).delivery)
    #expect(delivery.content == .speech)
    #expect(policy.canContinue(delivery, now: 699.9))
    #expect(!policy.canContinue(delivery, now: 700))
    #expect(policy.receive(event("after", created: 700, expires: 710), now: 700).delivery?.content == .cue)
}

@Test func connectingHeadphonesRevokesForceEvenWithSpeakersStillSelected() throws {
    var policy = VoicePolicy()
    policy.updateOutput(speakers, headphonesConnected: false)
    let enabled = policy.enableSpeaker(now: 100)
    #expect(enabled)
    let delivery = try #require(policy.receive(event(), now: 101).delivery)
    policy.updateOutput(speakers, headphonesConnected: true)
    #expect(!policy.canContinue(delivery, now: 102))
    let grantedWithHeadphones = policy.enableSpeaker(now: 102)
    #expect(!grantedWithHeadphones)
    policy.updateOutput(speakers, headphonesConnected: false)
    #expect(policy.receive(event("after"), now: 103).delivery?.content == .cue)
}

@Test func builtInOutputWithUnknownPortAllowsOnlyNeutralCue() {
    var policy = VoicePolicy()
    policy.updateOutput(OutputRoute(id: "laptop", device: 10, source: nil, kind: .cueOnly),
                        headphonesConnected: false)
    let granted = policy.enableSpeaker(now: 100)
    #expect(!granted)
    #expect(policy.receive(event(), now: 101).delivery?.content == .cue)
}

@Test func explicitActivityExtendsForceAndSuspensionCancelsIt() throws {
    var policy = VoicePolicy()
    policy.updateOutput(speakers, headphonesConnected: false)
    let enabled = policy.enableSpeaker(now: 100)
    #expect(enabled)
    policy.ownerInteraction(now: 650)
    let delivery = try #require(policy.receive(event(created: 749, expires: 770), now: 750).delivery)
    #expect(delivery.content == .speech)
    policy.setPaused(true)
    #expect(!policy.canContinue(delivery, now: 751))
    #expect(policy.receive(event("paused", created: 751, expires: 770), now: 751) == .skipped(.paused))
    policy.setPaused(false)
    #expect(policy.receive(event("fresh", created: 752, expires: 770), now: 752).delivery?.content == .cue)
}

@Test func lateDuplicateBusyAndObsoleteEventsNeverPlayLater() throws {
    var policy = VoicePolicy()
    policy.updateOutput(headphones, headphonesConnected: true)
    let delivery = try #require(policy.receive(event(), now: 101).delivery)
    #expect(!policy.canStart(delivery, now: 110))
    #expect(policy.receive(event("late"), now: 110) == .skipped(.stale))
    #expect(policy.receive(event("other"), now: 102, playing: true) == .skipped(.busy))
    #expect(policy.receive(event("other"), now: 103) == .skipped(.duplicate))
    #expect(policy.receive(event("prestart", created: 100), now: 103, notBefore: 102) == .skipped(.stale))
}

@Test func sameDeviceWithDifferentPhysicalSourceInvalidatesPreviousGrant() throws {
    var policy = VoicePolicy()
    policy.updateOutput(speakers, headphonesConnected: false)
    let enabled = policy.enableSpeaker(now: 100)
    #expect(enabled)
    let delivery = try #require(policy.receive(event(), now: 101).delivery)
    let changed = OutputRoute(id: speakers.id, device: speakers.device, source: 2, kind: .speakers)
    policy.updateOutput(changed, headphonesConnected: false)
    #expect(!policy.canContinue(delivery, now: 102))
    #expect(policy.receive(event("new"), now: 102).delivery?.content == .cue)
}

@Test func meetingBlocksBothSpeechAndCuesAndRevokesForce() throws {
    var policy = VoicePolicy()
    policy.updateOutput(speakers, headphonesConnected: false)
    let enabled = policy.enableSpeaker(now: 100)
    #expect(enabled)
    let delivery = try #require(policy.receive(event(), now: 101).delivery)

    policy.updateMeeting(.busy)
    #expect(!policy.canContinue(delivery, now: 102))
    let attemptedDuringMeeting = policy.enableSpeaker(now: 102)
    #expect(!attemptedDuringMeeting)
    #expect(policy.receive(event("blocked"), now: 102) == .skipped(.meeting))
    policy.updateMeeting(.unknown)
    #expect(policy.receive(event("unknown"), now: 103) == .skipped(.meeting))

    policy.updateMeeting(.clear)
    #expect(policy.receive(event("blocked"), now: 104) == .skipped(.duplicate))
    #expect(policy.receive(event("fresh"), now: 104).delivery?.content == .cue)
    #expect(!policy.canStart(delivery, now: 104))
}

@Test func meetingClearCannotOverrideManualPause() {
    var policy = VoicePolicy()
    policy.updateOutput(headphones, headphonesConnected: true)
    policy.setPaused(true)
    policy.updateMeeting(.busy)
    policy.updateMeeting(.clear)
    #expect(policy.receive(event(), now: 101) == .skipped(.paused))
}
