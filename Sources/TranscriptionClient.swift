import Foundation

class TranscriptionClient {
    let serverURL = URL(string: "http://127.0.0.1:9393")!

    /// Send audio file to Parakeet daemon, return transcribed text.
    func transcribe(audioURL: URL) async throws -> String {
        let url = serverURL.appendingPathComponent("transcribe")
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["file": audioURL.path]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 503 {
            throw TranscriptionError.modelNotReady
        }

        guard httpResponse.statusCode == 200 else {
            throw TranscriptionError.serverError(httpResponse.statusCode)
        }

        let json = try JSONDecoder().decode([String: String].self, from: data)

        if let errorMsg = json["error"] {
            throw TranscriptionError.transcriptionFailed(errorMsg)
        }

        return json["text"] ?? ""
    }

    /// Check if the daemon is running and model is loaded.
    func isReady() async -> Bool {
        await statusInfo().0
    }

    /// Returns (ready, infoString) from /status.
    func statusInfo() async -> (Bool, String) {
        let url = serverURL.appendingPathComponent("status")
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONDecoder().decode([String: AnyDecodable].self, from: data)
            let ready   = json["ready"]?.value as? Bool   ?? false
            let model   = json["model"]?.value  as? String ?? ""
            let error   = json["error"]?.value  as? String ?? ""
            let info    = ready ? model : (error.isEmpty ? model : error)
            return (ready, info)
        } catch {
            return (false, "Daemon nicht erreichbar")
        }
    }

    /// Poll /status until the model is ready or the timeout expires.
    func waitForReady(timeout: TimeInterval = 120) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isReady() { return true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return false
    }
}

enum TranscriptionError: LocalizedError {
    case invalidResponse
    case modelNotReady
    case serverError(Int)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:         return "Ungültige Antwort vom Transkriptions-Server."
        case .modelNotReady:           return "Parakeet-Modell noch nicht geladen. Bitte warten."
        case .serverError(let code):   return "Server-Fehler: HTTP \(code)"
        case .transcriptionFailed(let msg): return "Transkription fehlgeschlagen: \(msg)"
        }
    }
}

// Minimal type-erased Decodable for parsing heterogeneous JSON
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self)   { value = b; return }
        if let i = try? container.decode(Int.self)    { value = i; return }
        if let d = try? container.decode(Double.self) { value = d; return }
        if let s = try? container.decode(String.self) { value = s; return }
        value = NSNull()
    }
}
