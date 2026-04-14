import Foundation

struct AppConfig: Codable {
    var anthropicApiKey: String = ""
    /// "whisper" (mehrsprachig, Standard) oder "parakeet" (nur Englisch)
    var transcriptionBackend: String = "whisper"
    /// Whisper-Modellgröße: tiny | base | small | medium | large-v3
    var whisperModel: String = "large-v3"
    var language: String = "de"
    var autoPaste: Bool = false
    var autoCopy: Bool = true
    var assistantPrompt: String = "Du bist ein Assistent der gesprochene Texte bereinigt. Entferne Korrekturen (z.B. 'nein, 9:30 Uhr' → nur '9:30 Uhr'), Füllwörter und Wiederholungen. Behalte den Inhalt aber gib nur den finalen sauberen Text zurück."
    var dictationPrompt: String = "Wandle den folgenden gesprochenen Text in eine natürliche, gut geschriebene Nachricht um. Passe Stil, Grammatik und Formulierungen an, damit es wie ein professionell geschriebener Text klingt. Gib nur den finalen Text zurück ohne Erklärungen."
}

class SettingsManager {
    static let shared = SettingsManager()

    var config: AppConfig
    private let configURL: URL

    private init() {
        // Try Application Support first, fall back to bundle Resources
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceScribe")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        configURL = appSupport.appendingPathComponent("config.json")

        // Seed from bundle resource if no user config exists yet
        if !FileManager.default.fileExists(atPath: configURL.path),
           let bundleConfig = Bundle.main.url(forResource: "config", withExtension: "json") {
            try? FileManager.default.copyItem(at: bundleConfig, to: configURL)
        }

        config = Self.load(from: configURL)
    }

    private static func load(from url: URL) -> AppConfig {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        // Pretty-print
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? pretty.write(to: configURL, options: .atomic)
        } else {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    func reload() {
        config = Self.load(from: configURL)
    }
}
