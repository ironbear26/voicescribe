import AVFoundation
import Foundation

class AudioRecorder {
    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private(set) var isRecording = false
    private var outputURL: URL?

    /// Start recording microphone input to a temporary WAV file.
    /// Writes in the hardware's native format – NeMo/Parakeet resamples internally.
    func startRecording() throws -> URL {
        if isRecording { _ = stopRecording() }

        // Use outputFormat – this is what the input node delivers to the graph
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicescribe_\(Int(Date().timeIntervalSince1970)).wav")

        // Create the file with the exact same format as the tap – no conversion needed
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        outputURL = url

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let file = self?.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                // Silently ignore individual write failures to keep the tap alive
            }
        }

        try audioEngine.start()
        isRecording = true
        return url
    }

    /// Stop recording and return the URL of the recorded file (nil if nothing was recorded).
    func stopRecording() -> URL? {
        guard isRecording else { return outputURL }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil          // closes and flushes the file
        isRecording = false
        let url = outputURL
        outputURL = nil
        return url
    }
}
