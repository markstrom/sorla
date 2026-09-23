import AVFoundation
import os
import SorlaCore

@MainActor
final class FeedbackSoundPlayer {
    private static let logger = Logger(subsystem: "com.sorla.app", category: "FeedbackSoundPlayer")
    private let startPlayer = makePlayer(FeedbackSound.startSamples())
    private let stopPlayer = makePlayer(FeedbackSound.stopSamples())

    func playStart() {
        play(startPlayer)
    }

    func playStop() {
        play(stopPlayer)
    }

    // AVAudioPlayer plays on its own thread; play() only schedules the already prepared buffer.
    private func play(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private static func makePlayer(_ samples: [Float]) -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(data: WAVEncoder.encode(samples, sampleRate: FeedbackSound.sampleRate))
            player.prepareToPlay()
            return player
        } catch {
            logger.error("failed to create feedback sound player: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
