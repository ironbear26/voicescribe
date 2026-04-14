import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var apiKeyField: NSSecureTextField!
    private var autoPasteCheckbox: NSButton!
    private var autoCopyCheckbox: NSButton!
    private var backendPopup: NSPopUpButton!
    private var whisperModelPopup: NSPopUpButton!
    private var whisperModelLabel: NSTextField!
    private var modelStatusLabel: NSTextField!
    private var statusCheckTimer: Timer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceScribe – Einstellungen"
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let padding: CGFloat = 20
        let labelWidth: CGFloat = 170
        let fieldX = padding + labelWidth + 10
        let fieldWidth: CGFloat = 280
        var y: CGFloat = 365

        // MARK: – Transkriptions-Backend
        addLabel("Transkription:", x: padding, y: y, w: labelWidth, to: contentView)

        backendPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 2, width: 200, height: 24))
        backendPopup.addItems(withTitles: [
            "Whisper (Deutsch & mehr)",
            "Parakeet (nur Englisch)",
        ])
        let currentBackend = SettingsManager.shared.config.transcriptionBackend
        backendPopup.selectItem(at: currentBackend == "parakeet" ? 1 : 0)
        backendPopup.target = self
        backendPopup.action = #selector(backendChanged)
        contentView.addSubview(backendPopup)

        y -= 40

        // MARK: – Whisper-Modell
        whisperModelLabel = addLabel("Whisper-Modell:", x: padding, y: y, w: labelWidth, to: contentView)

        whisperModelPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 2, width: 200, height: 24))
        whisperModelPopup.addItems(withTitles: ["tiny", "base", "small", "medium", "large-v3"])
        whisperModelPopup.selectItem(withTitle: SettingsManager.shared.config.whisperModel)
        if whisperModelPopup.indexOfSelectedItem == -1 { whisperModelPopup.selectItem(at: 4) }
        contentView.addSubview(whisperModelPopup)

        let whisperNote = addLabel("↑ large-v3 = beste Qualität, ~3 GB", x: fieldX, y: y - 20, w: 280, to: contentView)
        whisperNote.textColor = .tertiaryLabelColor
        whisperNote.font = .systemFont(ofSize: 10)

        // Sichtbarkeit initial setzen
        updateWhisperModelVisibility()

        y -= 58

        // MARK: – API Key
        addLabel("Anthropic API-Key:", x: padding, y: y, w: labelWidth, to: contentView)
        apiKeyField = NSSecureTextField(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 24))
        apiKeyField.placeholderString = "sk-ant-..."
        apiKeyField.stringValue = SettingsManager.shared.config.anthropicApiKey
        contentView.addSubview(apiKeyField)

        y -= 40

        // MARK: – Auto-Copy
        autoCopyCheckbox = NSButton(checkboxWithTitle: "Ergebnis automatisch in Zwischenablage kopieren",
                                    target: nil, action: nil)
        autoCopyCheckbox.frame = NSRect(x: padding, y: y, width: 440, height: 20)
        autoCopyCheckbox.state = SettingsManager.shared.config.autoCopy ? .on : .off
        contentView.addSubview(autoCopyCheckbox)

        y -= 32

        // MARK: – Auto-Paste
        autoPasteCheckbox = NSButton(checkboxWithTitle: "Ergebnis automatisch einfügen (Cmd+V simulieren)",
                                     target: nil, action: nil)
        autoPasteCheckbox.frame = NSRect(x: padding, y: y, width: 440, height: 20)
        autoPasteCheckbox.state = SettingsManager.shared.config.autoPaste ? .on : .off
        contentView.addSubview(autoPasteCheckbox)

        y -= 44

        // MARK: – Modell-Status
        addLabel("Modell-Status:", x: padding, y: y, w: labelWidth, to: contentView)
        modelStatusLabel = addLabel("Prüfe...", x: fieldX, y: y, w: fieldWidth, to: contentView)
        modelStatusLabel.textColor = .secondaryLabelColor

        y -= 36

        // MARK: – Hotkey-Info
        let info = addLabel("Hotkeys: ⌃⇧T Transkript · ⌃⇧A Assistent · ⌃⇧D Diktat · ⌃⇧S Stop",
                            x: padding, y: y, w: 460, to: contentView)
        info.textColor = .tertiaryLabelColor
        info.font = .systemFont(ofSize: 11)

        // MARK: – Speichern-Button
        let saveBtn = NSButton(title: "Einstellungen speichern", target: self, action: #selector(saveSettings))
        saveBtn.frame = NSRect(x: contentView.bounds.width - 210 - padding, y: padding, width: 210, height: 32)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        contentView.addSubview(saveBtn)

        // Status-Polling
        refreshModelStatus()
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.refreshModelStatus()
        }
    }

    @discardableResult
    private func addLabel(_ title: String, x: CGFloat, y: CGFloat, w: CGFloat, to view: NSView) -> NSTextField {
        let tf = NSTextField(labelWithString: title)
        tf.frame = NSRect(x: x, y: y, width: w, height: 20)
        tf.isEditable = false
        tf.isBordered = false
        tf.backgroundColor = .clear
        view.addSubview(tf)
        return tf
    }

    @objc private func backendChanged() {
        updateWhisperModelVisibility()
    }

    private func updateWhisperModelVisibility() {
        let isWhisper = backendPopup.indexOfSelectedItem == 0
        whisperModelPopup.isHidden  = !isWhisper
        whisperModelLabel.isHidden  = !isWhisper
    }

    private func refreshModelStatus() {
        Task {
            let client = TranscriptionClient()
            let (ready, info) = await client.statusInfo()
            DispatchQueue.main.async {
                if ready {
                    self.modelStatusLabel.stringValue = "✓ Bereit (\(info))"
                    self.modelStatusLabel.textColor = .systemGreen
                } else {
                    self.modelStatusLabel.stringValue = "⏳ \(info.isEmpty ? "Lädt..." : info)"
                    self.modelStatusLabel.textColor = .secondaryLabelColor
                }
            }
        }
    }

    @objc private func saveSettings() {
        let isWhisper = backendPopup.indexOfSelectedItem == 0
        SettingsManager.shared.config.transcriptionBackend = isWhisper ? "whisper" : "parakeet"
        SettingsManager.shared.config.whisperModel         = whisperModelPopup.titleOfSelectedItem ?? "large-v3"
        SettingsManager.shared.config.anthropicApiKey      = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        SettingsManager.shared.config.autoPaste            = autoPasteCheckbox.state == .on
        SettingsManager.shared.config.autoCopy             = autoCopyCheckbox.state  == .on
        SettingsManager.shared.save()

        let alert = NSAlert()
        alert.messageText = "Einstellungen gespeichert"
        alert.informativeText = "Starte die App neu, damit das neue Transkriptions-Backend geladen wird."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil
    }
}
