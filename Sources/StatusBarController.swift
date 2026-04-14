import AppKit
import UserNotifications

enum RecordingMode {
    case transcript
    case assistant
    case dictation

    var displayName: String {
        switch self {
        case .transcript: return "Transkript"
        case .assistant:  return "Assistent"
        case .dictation:  return "Diktat"
        }
    }
}

class StatusBarController {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // Menu items we need to update at runtime
    private var statusMenuItem: NSMenuItem!
    private var autoPasteMenuItem: NSMenuItem!
    private var modelStatusMenuItem: NSMenuItem!
    private var lastTranscriptMenuItem: NSMenuItem!

    // Sub-controllers
    private let audioRecorder = AudioRecorder()
    private let transcriptionClient = TranscriptionClient()
    private let clipboardManager = ClipboardManager()
    private var hotkeyManager: HotkeyManager!
    private var settingsWindowController: SettingsWindowController?
    private var daemonProcess: Process?

    // State
    private var isRecording = false
    private var currentMode: RecordingMode = .transcript
    private var lastTranscript: String = ""
    private var currentAudioURL: URL?

    // MARK: - Setup

    func start() {
        setupStatusItem()
        buildMenu()
        startParakeetDaemon()
        setupHotkeys()
        requestNotificationPermission()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎙"
        statusItem.button?.font = NSFont.systemFont(ofSize: 16)
    }

    private func buildMenu() {
        menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "● Bereit", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let transcriptItem = NSMenuItem(title: "Transkript-Modus  ⌃⇧T", action: #selector(startTranscriptMode), keyEquivalent: "")
        transcriptItem.target = self
        menu.addItem(transcriptItem)

        let assistantItem = NSMenuItem(title: "Assistent-Modus  ⌃⇧A", action: #selector(startAssistantMode), keyEquivalent: "")
        assistantItem.target = self
        menu.addItem(assistantItem)

        let dictationItem = NSMenuItem(title: "Diktat-Modus  ⌃⇧D", action: #selector(startDictationMode), keyEquivalent: "")
        dictationItem.target = self
        menu.addItem(dictationItem)

        let stopItem = NSMenuItem(title: "Aufnahme stoppen  ⌃⇧S", action: #selector(stopRecordingFromMenu), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let autoPasteTitle = SettingsManager.shared.config.autoPaste ? "Auto-Einfügen: An" : "Auto-Einfügen: Aus"
        autoPasteMenuItem = NSMenuItem(title: autoPasteTitle, action: #selector(toggleAutoPaste), keyEquivalent: "")
        autoPasteMenuItem.target = self
        autoPasteMenuItem.state = SettingsManager.shared.config.autoPaste ? .on : .off
        menu.addItem(autoPasteMenuItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Einstellungen...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        lastTranscriptMenuItem = NSMenuItem(title: "Letztes Transkript anzeigen", action: #selector(showLastTranscript), keyEquivalent: "")
        lastTranscriptMenuItem.target = self
        menu.addItem(lastTranscriptMenuItem)

        menu.addItem(NSMenuItem.separator())

        modelStatusMenuItem = NSMenuItem(title: "Modell-Status: Prüfe...", action: nil, keyEquivalent: "")
        modelStatusMenuItem.isEnabled = false
        menu.addItem(modelStatusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Poll model status every 5 seconds
        checkModelStatus()
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkModelStatus()
        }
    }

    private func setupHotkeys() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onTranscript = { [weak self] in self?.startMode(.transcript) }
        hotkeyManager.onAssistant  = { [weak self] in self?.startMode(.assistant) }
        hotkeyManager.onDictation  = { [weak self] in self?.startMode(.dictation) }
        hotkeyManager.onStop       = { [weak self] in self?.stopAndProcess() }
        hotkeyManager.register()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Daemon Management

    func startParakeetDaemon() {
        // Resolve server.py path
        let serverPath: String
        if let bundleRes = Bundle.main.resourceURL?.appendingPathComponent("python/server.py").path,
           FileManager.default.fileExists(atPath: bundleRes) {
            serverPath = bundleRes
        } else {
            // Development fallback: relative to executable
            let exeDir = (Bundle.main.executablePath! as NSString).deletingLastPathComponent
            let devPath = (exeDir as NSString).appendingPathComponent("../../python/server.py")
                .standardizingPath  // no method available here, use URL
            serverPath = URL(fileURLWithPath: devPath).standardized.path
        }

        // Resolve python path from venv
        let venvPython = (NSString("~/Library/Application Support/VoiceScribe/venv/bin/python3") as String)
            .replacingOccurrences(of: "~", with: NSHomeDirectory())

        let pythonExec = FileManager.default.fileExists(atPath: venvPython) ? venvPython : "/usr/bin/env python3"

        guard FileManager.default.fileExists(atPath: serverPath.hasPrefix("/") ? serverPath : "/" + serverPath) ||
              FileManager.default.fileExists(atPath: serverPath) else {
            DispatchQueue.main.async {
                self.modelStatusMenuItem?.title = "Modell-Status: server.py nicht gefunden"
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonExec.hasPrefix("/usr/bin/env") ? "/usr/bin/env" : pythonExec)
        if pythonExec.hasPrefix("/usr/bin/env") {
            process.arguments = ["python3", serverPath]
        } else {
            process.arguments = [serverPath]
        }

        // Pass current environment so venv packages are visible
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/VoiceScribe")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("daemon.log")
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        if let fh = try? FileHandle(forWritingTo: logFile) {
            process.standardOutput = fh
            process.standardError = fh
        }

        do {
            try process.run()
            daemonProcess = process
        } catch {
            DispatchQueue.main.async {
                self.modelStatusMenuItem?.title = "Modell-Status: Daemon-Start fehlgeschlagen"
            }
        }
    }

    func cleanup() {
        daemonProcess?.terminate()
        hotkeyManager?.unregister()
    }

    // MARK: - Recording Workflow

    func startMode(_ mode: RecordingMode) {
        if isRecording {
            stopAndProcess()
        } else {
            startRecording(mode: mode)
        }
    }

    private func startRecording(mode: RecordingMode) {
        currentMode = mode
        do {
            currentAudioURL = try audioRecorder.startRecording()
            isRecording = true
            DispatchQueue.main.async {
                self.statusItem.button?.title = "🔴"
                self.statusMenuItem.title = "⏺ Aufnahme läuft... (\(mode.displayName))"
            }
        } catch {
            showAlert(title: "Aufnahmefehler", message: error.localizedDescription)
        }
    }

    func stopAndProcess() {
        guard isRecording else { return }
        isRecording = false

        DispatchQueue.main.async {
            self.statusItem.button?.title = "⚙️"
            self.statusMenuItem.title = "⚙ Stoppe Aufnahme..."
        }

        guard let wavURL = audioRecorder.stopRecording() else {
            updateStatus(title: "🎙", status: "● Bereit")
            return
        }

        Task {
            await processAudio(at: wavURL)
        }
    }

    private func processAudio(at wavURL: URL) async {
        updateStatus(title: "⚙️", status: "⚙ Transkribiere (Parakeet)...")

        var text: String
        do {
            text = try await transcriptionClient.transcribe(audioURL: wavURL)
        } catch {
            updateStatus(title: "🎙", status: "● Bereit")
            showAlert(title: "Transkriptionsfehler", message: error.localizedDescription)
            try? FileManager.default.removeItem(at: wavURL)
            return
        }

        if text.isEmpty {
            updateStatus(title: "🎙", status: "● Bereit (kein Text)")
            try? FileManager.default.removeItem(at: wavURL)
            return
        }

        // Claude post-processing
        if currentMode == .assistant || currentMode == .dictation {
            let assistantClient = AssistantClient()
            let apiKey = SettingsManager.shared.config.anthropicApiKey
            guard !apiKey.isEmpty else {
                showAlert(title: "API-Key fehlt", message: "Bitte Anthropic API-Key in den Einstellungen eintragen.")
                updateStatus(title: "🎙", status: "● Bereit")
                try? FileManager.default.removeItem(at: wavURL)
                return
            }
            assistantClient.apiKey = apiKey

            do {
                if currentMode == .assistant {
                    updateStatus(title: "⚙️", status: "⚙ Claude bereinigt Text...")
                    text = try await assistantClient.cleanTranscript(text)
                } else {
                    updateStatus(title: "⚙️", status: "⚙ Claude formatiert Diktat...")
                    text = try await assistantClient.dictationMode(text)
                }
            } catch {
                // Non-fatal: use raw transcript
                print("AssistantClient error: \(error)")
            }
        }

        // Copy & paste (capture final text value explicitly for Swift 6 sendability)
        let settings = SettingsManager.shared.config
        let finalText = text
        if settings.autoCopy {
            await MainActor.run { self.clipboardManager.copy(finalText) }
        }
        if settings.autoPaste {
            await MainActor.run { self.clipboardManager.paste() }
        }

        lastTranscript = text
        sendNotification(text: text)
        updateStatus(title: "✅", status: "✓ Fertig")

        // Reset after 2 seconds
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        updateStatus(title: "🎙", status: "● Bereit")

        try? FileManager.default.removeItem(at: wavURL)
    }

    // MARK: - Model Status

    private func checkModelStatus() {
        let client = transcriptionClient
        Task { @MainActor in
            let ready = await client.isReady()
            let title = ready ? "Modell-Status: ✓ Parakeet bereit" : "Modell-Status: ⏳ Lädt..."
            self.modelStatusMenuItem?.title = title
        }
    }

    // MARK: - Notifications

    private func sendNotification(text: String) {
        let content = UNMutableNotificationContent()
        content.title = "VoiceScribe"
        let preview = text.count > 100 ? String(text.prefix(100)) + "…" : text
        content.body = preview
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - UI Helpers

    private func updateStatus(title: String, status: String) {
        DispatchQueue.main.async {
            self.statusItem.button?.title = title
            self.statusMenuItem.title = status
        }
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Menu Actions

    @objc private func startTranscriptMode() { startMode(.transcript) }
    @objc private func startAssistantMode()  { startMode(.assistant) }
    @objc private func startDictationMode()  { startMode(.dictation) }

    @objc private func stopRecordingFromMenu() {
        if isRecording { stopAndProcess() }
    }

    @objc private func toggleAutoPaste() {
        SettingsManager.shared.config.autoPaste.toggle()
        SettingsManager.shared.save()
        let on = SettingsManager.shared.config.autoPaste
        autoPasteMenuItem.title = on ? "Auto-Einfügen: An" : "Auto-Einfügen: Aus"
        autoPasteMenuItem.state = on ? .on : .off
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showLastTranscript() {
        let alert = NSAlert()
        alert.messageText = "Letztes Transkript"
        alert.informativeText = lastTranscript.isEmpty ? "(noch kein Transkript)" : lastTranscript
        alert.addButton(withTitle: "Schließen")
        if !lastTranscript.isEmpty {
            alert.addButton(withTitle: "Kopieren")
        }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            clipboardManager.copy(lastTranscript)
        }
    }
}

// String extension for standardizing paths (simple helper)
private extension String {
    var standardizingPath: String {
        return URL(fileURLWithPath: self).standardized.path
    }
}
