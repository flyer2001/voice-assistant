import AVFoundation

/// Records 16 kHz mono PCM WAV. Backend accepts caf/wav/ogg/m4a/mp3
/// (see specs/backend-protocol.md).
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var currentURL: URL?

    func start() throws {
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("ptt-\(Int(Date().timeIntervalSince1970)).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.record()
        recorder = rec
        currentURL = url
    }

    func stop() -> URL? {
        recorder?.stop()
        let url = currentURL
        recorder = nil
        currentURL = nil
        return url
    }

    var isRecording: Bool { recorder?.isRecording ?? false }
}
