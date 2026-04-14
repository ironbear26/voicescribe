import Foundation

class AssistantClient {
    var apiKey: String = ""
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5-20251001"

    /// Clean up a raw transcript (remove filler words, corrections, repetitions).
    func cleanTranscript(_ text: String) async throws -> String {
        let system = SettingsManager.shared.config.assistantPrompt
        return try await callClaude(system: system, user: text)
    }

    /// Reformat dictated text into a polished written message.
    func dictationMode(_ text: String) async throws -> String {
        let system = SettingsManager.shared.config.dictationPrompt
        return try await callClaude(system: system, user: text)
    }

    private func callClaude(system: String, user: String) async throws -> String {
        var request = URLRequest(url: apiURL, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssistantError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AssistantError.apiError(httpResponse.statusCode, body)
        }

        // Parse: {"content": [{"type": "text", "text": "..."}], ...}
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first,
            let text = first["text"] as? String
        else {
            throw AssistantError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AssistantError: LocalizedError {
    case invalidResponse
    case apiError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:           return "Ungültige Antwort von der Anthropic API."
        case .apiError(let code, let msg): return "API-Fehler \(code): \(msg)"
        case .parseError:                return "Antwort der Anthropic API konnte nicht geparst werden."
        }
    }
}
