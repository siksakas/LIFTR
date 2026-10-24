//
//  QuickVoiceLog.swift
//  LIFTR
//

import AVFoundation
import Foundation
import Observation
import Speech

/// "Or just say it" on the Log screen: listens for one short sentence like
/// "I smoked three cigarettes" with on-device speech recognition and hands back the text.
/// For a whole conversation about the day, Coach's voice mode talks to the ElevenLabs partner.
@Observable
final class QuickVoiceLog {
    enum State: Equatable {
        case idle
        case listening
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var transcript = ""

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var stopTimer: Task<Void, Never>?
    @ObservationIgnored private var onFinish: ((String) -> Void)?

    /// Starts listening. `onFinish` gets what was said once the user pauses or taps again.
    func start(onFinish: @escaping (String) -> Void) async {
        guard state != .listening else { return }
        guard await Self.speechAllowed() else {
            state = .failed("Allow speech recognition for LIFTR in Settings to log by voice.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed("Allow the microphone for LIFTR in Settings to log by voice.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            state = .failed("Speech recognition isn't available right now.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

            // The tap runs on the audio thread.
            nonisolated(unsafe) let tapRequest = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { @Sendable buffer, _ in
                tapRequest.append(buffer)
            }
            engine.prepare()
            try engine.start()

            self.request = request
            self.onFinish = onFinish
            transcript = ""
            state = .listening
            task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isDone = (result?.isFinal ?? false) || error != nil
                Task { @MainActor in self?.receive(text, isDone: isDone) }
            }
            stopAfter(seconds: 10)
        } catch {
            tearDown()
            state = .failed("Couldn't start listening: \(error.localizedDescription)")
        }
    }

    /// Stops listening and uses what was heard so far.
    func finish() {
        guard state == .listening else { return }
        tearDown()
        state = .idle
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let handler = onFinish
        onFinish = nil
        if !text.isEmpty { handler?(text) }
    }

    func cancel() {
        onFinish = nil
        tearDown()
        state = .idle
    }

    private func receive(_ text: String?, isDone: Bool) {
        guard state == .listening else { return }
        if let text, !text.isEmpty {
            transcript = text
            // A short pause after speaking ends the sentence.
            stopAfter(seconds: 1.4)
        }
        if isDone { finish() }
    }

    private func stopAfter(seconds: Double) {
        stopTimer?.cancel()
        stopTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func tearDown() {
        stopTimer?.cancel()
        stopTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated private static func speechAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

/// Turns "I smoked three cigarettes and a vape" into counts per product.
enum VoiceLogParser {
    private static let numbers: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "once": 1, "single": 1,
        "two": 2, "twice": 2, "couple": 2, "pair": 2, "three": 3, "few": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20,
        // "I didn't smoke today" and "no cigarettes" mean zero, not one.
        "no": 0, "zero": 0, "none": 0, "not": 0, "never": 0, "didn": 0, "haven": 0, "hasn": 0, "wasn": 0,
    ]

    private static let nouns: [String: Product] = [
        "cigarette": .cigarette, "cigarettes": .cigarette, "cig": .cigarette, "cigs": .cigarette,
        "ciggie": .cigarette, "ciggies": .cigarette, "smokes": .cigarette,
        "vape": .vape, "vapes": .vape,
        "pouch": .pouch, "pouches": .pouch, "zyn": .pouch, "zyns": .pouch, "snus": .pouch,
    ]

    /// Verbs that name the product when the sentence leaves it out: "I smoked three".
    private static let verbs: [String: Product] = [
        "smoke": .cigarette, "smoked": .cigarette, "smoking": .cigarette,
        "vaped": .vape, "vaping": .vape,
    ]

    /// Words that can sit between a number and its product: "two more cigarettes".
    /// "t" is what's left of "didn't" once the apostrophe splits it.
    private static let fillers: Set<String> = ["more", "extra", "other", "of", "the", "quick", "little", "small", "whole", "full", "t", "any"]

    static func parse(_ sentence: String) -> [Product: Int] {
        let words = sentence.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        var counts: [Product: Int] = [:]
        var pending: Int?
        var verbProduct: Product?

        for word in words {
            if let number = Int(word) ?? numbers[word] {
                pending = number
            } else if let product = nouns[word] {
                counts[product, default: 0] += pending ?? 1
                pending = nil
                verbProduct = nil
            } else if let product = verbs[word] {
                verbProduct = product
            } else if !fillers.contains(word) {
                if let number = pending, let product = verbProduct {
                    counts[product, default: 0] += number
                    verbProduct = nil
                }
                pending = nil
            }
        }
        if let number = pending, let product = verbProduct {
            counts[product, default: 0] += number
        }
        return counts.mapValues { min($0, 40) }.filter { $0.value > 0 }
    }
}
