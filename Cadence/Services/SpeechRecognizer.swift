import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var authorized = false
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func requestAuth() async {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        authorized = (speech == .authorized)
        if !authorized {
            errorMessage = "Speech not authorized. Grant in System Settings → Privacy → Speech Recognition."
        }
    }

    func toggle() async {
        if isListening {
            stop()
        } else {
            if !authorized { await requestAuth() }
            guard authorized else { return }
            start()
        }
    }

    private func start() {
        transcript = ""
        errorMessage = nil
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Recognizer unavailable."
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.request?.append(buf)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorMessage = "Audio engine: \(error.localizedDescription)"
            return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let r = result {
                Task { @MainActor in self.transcript = r.bestTranscription.formattedString }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in self.stop() }
            }
        }
        isListening = true
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }
}
