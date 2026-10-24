//
//  VoiceNotes.swift
//  LIFTR
//

import AVFoundation
import Foundation
import Observation

/// Plays one voice note at a time and reports how far along it is, for the waveform.
@Observable
final class VoiceNotePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var playingURL: URL?
    private(set) var progress = 0.0
    private(set) var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func isPlaying(_ url: URL) -> Bool { playingURL == url }

    func toggle(_ url: URL) {
        if isPlaying(url) {
            stop()
        } else {
            play(url)
        }
    }

    func play(_ url: URL) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            self.player = player
            playingURL = url
            errorMessage = nil
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, let player = self.player, player.duration > 0 else { return }
                    self.progress = player.currentTime / player.duration
                }
            }
        } catch {
            errorMessage = "Couldn't play that voice note."
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        playingURL = nil
        progress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }

    /// Length of an audio file in seconds, or nil if it can't be read.
    static func duration(of url: URL) -> Double? {
        (try? AVAudioPlayer(contentsOf: url)).map(\.duration)
    }
}

/// Records a short voice note, for when someone records one on the user's phone.
@Observable
final class VoiceNoteRecorder {
    private(set) var isRecording = false
    private(set) var elapsed = 0.0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    static let maxDuration = 120.0

    /// Starts recording to `url`. Returns false if the microphone isn't allowed or available.
    func start(to url: URL) async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try AVAudioSession.sharedInstance().setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record(forDuration: Self.maxDuration) else { return false }
            self.recorder = recorder
            isRecording = true
            elapsed = 0
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, let recorder = self.recorder else { return }
                    if recorder.isRecording {
                        self.elapsed = recorder.currentTime
                    } else {
                        self.isRecording = false
                        return
                    }
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// Stops and returns the length in seconds.
    @discardableResult
    func stop() -> Double {
        let length = max(recorder?.currentTime ?? 0, elapsed)
        recorder?.stop()
        recorder = nil
        ticker?.cancel()
        ticker = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return length
    }
}

extension Double {
    /// "0:18"
    var minutesAndSeconds: String {
        let seconds = Int(rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
