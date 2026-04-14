import AVFoundation
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine
    private var inputNode: AVAudioInputNode
    private var audioFile: AVAudioFile?
    private(set) var isRecording = false
    private var outputURL: URL?

    init() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
    }

    /// Start recording microphone input to a temporary WAV file.
    /// Returns the URL of the output file.
    func startRecording() throws -> URL {
        // Clean up any previous tap
        if isRecording {
            _ = stopRecording()
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voicescribe_\(Int(Date().timeIntervalSince1970)).wav"
        let url = tempDir.appendingPathComponent(fileName)

        // Input format from hardware
        let hwFormat = inputNode.inputFormat(forBus: 0)

        // We want 16 kHz mono for best Parakeet compatibility
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw RecorderError.formatUnavailable
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw RecorderError.converterUnavailable
        }

        audioFile = try AVAudioFile(forWriting: url, settings: targetFormat.settings)
        outputURL = url

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self, let outFile = self.audioFile else { return }

            // Convert buffer to target format
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / hwFormat.sampleRate + 1
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            var inputConsumed = false
            converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil && convertedBuffer.frameLength > 0 {
                try? outFile.write(from: convertedBuffer)
            }
        }

        try audioEngine.start()
        isRecording = true
        return url
    }

    /// Stop recording and return the URL of the recorded file.
    func stopRecording() -> URL? {
        guard isRecording else { return outputURL }
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false
        let url = outputURL
        outputURL = nil
        return url
    }
}

enum RecorderError: LocalizedError {
    case formatUnavailable
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .formatUnavailable:  return "Zielformat (16kHz mono) konnte nicht erstellt werden."
        case .converterUnavailable: return "Audio-Konverter konnte nicht initialisiert werden."
        }
    }
}
