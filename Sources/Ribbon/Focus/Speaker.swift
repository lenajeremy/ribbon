import AVFoundation

/// Plays the orb's voice and reports how loud it is right now, so the orb can pulse along.
@MainActor final class Speaker {
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()

    func play(_ mp3: Data) {
        stop()
        player = try? AVAudioPlayer(data: mp3)
        player?.isMeteringEnabled = true
        player?.play()
    }

    /// Built-in macOS voice, used when the OpenAI voice isn't available.
    func say(_ text: String) {
        stop()
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// 0…1
    func level() -> Double {
        if let player, player.isPlaying {
            player.updateMeters()
            let amplitude = pow(10, Double(player.averagePower(forChannel: 0)) / 20)
            return min(1, amplitude * 2.5)
        }
        if synthesizer.isSpeaking {
            return 0.3 + 0.2 * sin(Date().timeIntervalSinceReferenceDate * 14)
        }
        return 0
    }
}
