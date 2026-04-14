import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var apiKeyField: NSSecureTextField!
    private var autoPasteCheckbox: NSButton!
    private var autoCopyCheckbox: NSButton!
    private var modelStatusLabel: NSTextField!
    private var statusCheckTimer: Timer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
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
        contentView.wantsLayer = true

        let padding: CGFloat = 20
        let labelWidth: CGFloat = 160
        let fieldWidth: CGFloat = 260
        var y: CGFloat = 280

        // MARK: - API Key
        let apiLabel = makeLabel("Anthropic API-Key:")
        apiLabel.frame = NSRect(x: padding, y: y, width: labelWidth, height: 20)
        contentView.addSubview(apiLabel)

        apiKeyField = NSSecureTextField(frame: NSRect(x: padding + labelWidth + 10, y: y - 2, width: fieldWidth, height: 24))
        apiKeyField.placeholderString = "sk-ant-..."
        apiKeyField.stringValue = SettingsManager.shared.config.anthropicApiKey
        contentView.addSubview(apiKeyField)

        y -= 50

        // MARK: - Auto-Copy
        autoCopyCheckbox = NSButton(checkboxWithTitle: "Text automatisch in Zwischenablage kopieren",
                                    target: nil, action: nil)
        autoCopyCheckbox.frame = NSRect(x: padding, y: y, width: 400, height: 20)
        autoCopyCheckbox.state = SettingsManager.shared.config.autoCopy ? .on : .off
        contentView.addSubview(autoCopyCheckbox)

        y -= 36

        // MARK: - Auto-Paste
        autoPasteCheckbox = NSButton(checkboxWithTitle: "Text automatisch einfügen (Cmd+V simulieren)",
                                     target: nil, action: nil)
        autoPasteCheckbox.frame = NSRect(x: padding, y: y, width: 400, height: 20)
        autoPasteCheckbox.state = SettingsManager.shared.config.autoPaste ? .on : .off
        contentView.addSubview(autoPasteCheckbox)

        y -= 50

        // MARK: - Model Status
        let modelLabel = makeLabel("Parakeet-Status:")
        modelLabel.frame = NSRect(x: padding, y: y, width: labelWidth, height: 20)
        contentView.addSubview(modelLabel)

        modelStatusLabel = makeLabel("Prüfe...")
        modelStatusLabel.frame = NSRect(x: padding + labelWidth + 10, y: y, width: fieldWidth, height: 20)
        modelStatusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(modelStatusLabel)

        y -= 50

        // MARK: - Hotkey info
        let hotkeyInfo = makeLabel("Hotkeys: ⌃⇧T Transkript · ⌃⇧A Assistent · ⌃⇧D Diktat · ⌃⇧S Stop")
        hotkeyInfo.frame = NSRect(x: padding, y: y, width: 440, height: 20)
        hotkeyInfo.textColor = .tertiaryLabelColor
        contentView.addSubview(hotkeyInfo)

        y -= 50

        // MARK: - Save button
        let saveButton = NSButton(title: "Einstellungen speichern", target: self, action: #selector(saveSettings))
        saveButton.frame = NSRect(x: contentView.bounds.width - 200 - padding, y: padding, width: 200, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        // Start polling model status
        refreshModelStatus()
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.refreshModelStatus()
        }
    }

    private func makeLabel(_ title: String) -> NSTextField {
        let tf = NSTextField(labelWithString: title)
        tf.isEditable = false
        tf.isBordered = false
        tf.backgroundColor = .clear
        return tf
    }

    private func refreshModelStatus() {
        Task {
            let client = TranscriptionClient()
            let ready = await client.isReady()
            DispatchQueue.main.async {
                self.modelStatusLabel.stringValue = ready ? "✓ Bereit (nvidia/parakeet-tdt-0.6b-v2)" : "⏳ Lädt noch..."
                self.modelStatusLabel.textColor = ready ? NSColor.systemGreen : NSColor.secondaryLabelColor
            }
        }
    }

    @objc private func saveSettings() {
        SettingsManager.shared.config.anthropicApiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        SettingsManager.shared.config.autoPaste = autoPasteCheckbox.state == .on
        SettingsManager.shared.config.autoCopy  = autoCopyCheckbox.state  == .on
        SettingsManager.shared.save()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil
    }
}
