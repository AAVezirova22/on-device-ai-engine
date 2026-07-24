import AppKit
import Carbon
import EdgeAIEngine
import Foundation
import ServiceManagement

private final class HotkeyRunner {
    static let shared = HotkeyRunner()

    var statusHandler: ((String) -> Void)?

    private init() {}

    func summarizeClipboard() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notify("Clipboard has no text.")
            NSSound.beep()
            return
        }

        notify("Summarizing clipboard…")

        Task {
            do {
                let answer = try await summarize(text: text)

                await MainActor.run {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(answer, forType: .string)
                    notify("Summary copied to clipboard.")
                }
            } catch {
                await MainActor.run {
                    notify("Summary failed.")
                    NSAlert.showEdgeAIError(message: String(describing: error))
                }
            }
        }
    }

    private func summarize(text: String) async throws -> String {
        let document = LocalDocument(sourcePath: "clipboard", title: "Clipboard", body: text)
        let chunks = RecursiveChunker(targetWords: 140, overlapWords: 20).chunk(document)
        let embeddingModel = try configuredEmbeddingModel()
        var index = VectorIndex(embeddingDimensions: embeddingModel.dimensions)
        index.add(chunks, using: embeddingModel)

        let engine = RAGEngine(
            index: index,
            embeddingModel: embeddingModel,
            llm: ExtractiveLocalLLM()
        )

        let result = try await engine.answer(
            question: "Summarize this text and extract action items.",
            topK: 4
        )
        return result.answer
    }

    private func configuredEmbeddingModel() throws -> EmbeddingModel {
        let configURL = URL(fileURLWithPath: EdgeAIConfigurationStore.defaultPath)
        let configuration = try EdgeAIConfigurationStore.loadIfPresent(from: configURL) ?? .default
        return try EmbeddingModelFactory.make(identifier: configuration.embeddingModel)
    }

    private func notify(_ message: String) {
        print(message)
        statusHandler?(message)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerInstalled = false
    private var statusItem: NSStatusItem?
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenuBar()
        configureStatusUpdates()
        registerHotkey()
        updateLaunchAtLoginMenuItem()
        showOnboardingIfNeeded()
    }

    private func configureMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "EdgeAI"
        statusItem.button?.toolTip = "On-Device AI Engine"

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Summarize Clipboard",
                action: #selector(summarizeClipboard),
                keyEquivalent: "s"
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Preferences…",
                action: #selector(showPreferences),
                keyEquivalent: ","
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "About On-Device AI Engine",
                action: #selector(showAbout),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            NSMenuItem(
                title: "Privacy & Permissions",
                action: #selector(showPrivacyAndPermissions),
                keyEquivalent: ""
            )
        )
        menu.addItem(launchAtLoginMenuItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func configureStatusUpdates() {
        HotkeyRunner.shared.statusHandler = { [weak self] message in
            DispatchQueue.main.async {
                self?.setStatus(message)
            }
        }
    }

    private func setStatus(_ message: String) {
        statusMenuItem.title = message
        statusItem?.button?.toolTip = message
    }

    private func registerHotkey() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }

        let configuredHotkey: CarbonHotkey
        do {
            configuredHotkey = try CarbonHotkey.loadFromConfiguration()
        } catch {
            configuredHotkey = .default
            setStatus("Invalid configured hotkey; using ⌃⌥⌘S.")
        }

        let hotKeyID = EventHotKeyID(signature: fourCharacterCode("EAIE"), id: 1)

        let status = RegisterEventHotKey(
            configuredHotkey.keyCode,
            configuredHotkey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard status == noErr else {
            setStatus("Hotkey registration failed: \(status)")
            return
        }

        setStatus("Ready. Press \(configuredHotkey.displayName).")

        guard !eventHandlerInstalled else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async {
                    HotkeyRunner.shared.summarizeClipboard()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        eventHandlerInstalled = true
    }

    @objc private func summarizeClipboard() {
        HotkeyRunner.shared.summarizeClipboard()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "On-Device AI Engine"
        alert.informativeText = """
        Privacy-first local document and clipboard assistant.

        Copy text from any app, then press Control+Option+Command+S. The summary is written back to the clipboard.
        """
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func showPrivacyAndPermissions() {
        let alert = NSAlert()
        alert.messageText = "Privacy & Permissions"
        alert.informativeText = """
        On-Device AI Engine processes clipboard text locally.

        The app reads the clipboard only when you choose Summarize Clipboard or press the configured global hotkey. The default fallback and Apple NaturalLanguage embeddings run on-device. Network access is used only if you configure a llama.cpp server URL.

        Launch at Login requires a signed app and may require approval in System Settings → General → Login Items.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Login Items")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func showPreferences() {
        do {
            let configURL = URL(fileURLWithPath: EdgeAIConfigurationStore.defaultPath)
            var configuration = try EdgeAIConfigurationStore.loadIfPresent(from: configURL) ?? .default

            let embeddingPopup = NSPopUpButton()
            embeddingPopup.addItems(withTitles: ["hash", "natural"])
            embeddingPopup.selectItem(withTitle: configuration.embeddingModel)

            let keyField = NSTextField(string: configuration.hotkey.key.uppercased())
            keyField.maximumNumberOfLines = 1

            let controlBox = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
            let optionBox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
            let commandBox = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
            let shiftBox = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)

            let modifiers = Set(configuration.hotkey.modifiers.map { $0.lowercased() })
            controlBox.state = modifiers.contains("control") ? .on : .off
            optionBox.state = modifiers.contains("option") ? .on : .off
            commandBox.state = modifiers.contains("command") ? .on : .off
            shiftBox.state = modifiers.contains("shift") ? .on : .off

            let modifierStack = NSStackView(views: [controlBox, optionBox, commandBox, shiftBox])
            modifierStack.orientation = .vertical
            modifierStack.alignment = .leading

            let form = NSGridView(views: [
                [NSTextField.preferenceLabel("Embedding"), embeddingPopup],
                [NSTextField.preferenceLabel("Hotkey key"), keyField],
                [NSTextField.preferenceLabel("Modifiers"), modifierStack]
            ])
            form.rowSpacing = 10
            form.columnSpacing = 14

            let alert = NSAlert()
            alert.messageText = "Preferences"
            alert.informativeText = "Settings are saved to .edgeai/config.json."
            alert.accessoryView = form
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }

            let selectedModifiers: [String] = [
                (controlBox, "control"),
                (optionBox, "option"),
                (commandBox, "command"),
                (shiftBox, "shift")
            ].compactMap { checkbox, value in
                checkbox.state == .on ? String(value) : nil
            }

            configuration.embeddingModel = embeddingPopup.titleOfSelectedItem ?? "hash"
            configuration.hotkey = HotkeyConfiguration(
                key: keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                modifiers: selectedModifiers
            )

            _ = try CarbonHotkey(configuration: configuration.hotkey)
            _ = try EmbeddingModelFactory.make(identifier: configuration.embeddingModel)
            try EdgeAIConfigurationStore.save(configuration, to: configURL)
            registerHotkey()
            setStatus("Preferences saved.")
        } catch {
            NSAlert.showEdgeAIError(message: String(describing: error))
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
                setStatus("Launch at Login disabled.")
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
                setStatus("Launch at Login enabled.")
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
                setStatus("Approve Launch at Login in System Settings.")
            @unknown default:
                try SMAppService.mainApp.register()
                setStatus("Launch at Login requested.")
            }
            updateLaunchAtLoginMenuItem()
        } catch {
            updateLaunchAtLoginMenuItem()
            NSAlert.showEdgeAIError(
                message: """
                Could not update Launch at Login.

                \(error)

                If this is an unsigned local build, package, sign, and notarize the app before enabling Launch at Login.
                """
            )
        }
    }

    private func updateLaunchAtLoginMenuItem() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginMenuItem.state = .on
            launchAtLoginMenuItem.title = "Launch at Login"
        case .requiresApproval:
            launchAtLoginMenuItem.state = .mixed
            launchAtLoginMenuItem.title = "Launch at Login — Requires Approval"
        case .notFound:
            launchAtLoginMenuItem.state = .off
            launchAtLoginMenuItem.title = "Launch at Login — App Not Found"
        case .notRegistered:
            launchAtLoginMenuItem.state = .off
            launchAtLoginMenuItem.title = "Launch at Login"
        @unknown default:
            launchAtLoginMenuItem.state = .off
            launchAtLoginMenuItem.title = "Launch at Login — Unknown"
        }
    }

    private func showOnboardingIfNeeded() {
        let key = "EdgeAIHotkeyOnboardingShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "On-Device AI Engine is running"
        alert.informativeText = """
        Copy text from any app, then press the configured hotkey or choose Summarize Clipboard from the EdgeAI menu.

        Default hotkey: Control+Option+Command+S.

        Clipboard text is processed locally unless you explicitly configure a llama.cpp server.
        """
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private struct CarbonHotkey {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    init(keyCode: UInt32, modifiers: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }

    static let `default` = CarbonHotkey(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        displayName: "⌃⌥⌘S"
    )

    static func loadFromConfiguration() throws -> CarbonHotkey {
        let configURL = URL(fileURLWithPath: EdgeAIConfigurationStore.defaultPath)
        let configuration = try EdgeAIConfigurationStore.loadIfPresent(from: configURL) ?? .default
        return try CarbonHotkey(configuration: configuration.hotkey)
    }

    init(configuration: HotkeyConfiguration) throws {
        let key = configuration.key.lowercased()
        guard let keyCode = Self.keyCodes[key] else {
            throw HotkeyConfigurationError.unsupportedKey(configuration.key)
        }

        var modifiers: UInt32 = 0
        var symbols: [String] = []

        for modifier in configuration.modifiers.map({ $0.lowercased() }) {
            switch modifier {
            case "control", "ctrl":
                modifiers |= UInt32(controlKey)
                symbols.append("⌃")
            case "option", "alt":
                modifiers |= UInt32(optionKey)
                symbols.append("⌥")
            case "command", "cmd", "meta":
                modifiers |= UInt32(cmdKey)
                symbols.append("⌘")
            case "shift":
                modifiers |= UInt32(shiftKey)
                symbols.append("⇧")
            default:
                throw HotkeyConfigurationError.unsupportedModifier(modifier)
            }
        }

        guard modifiers != 0 else {
            throw HotkeyConfigurationError.noModifiers
        }

        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers
        self.displayName = symbols.joined() + key.uppercased()
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A,
        "b": kVK_ANSI_B,
        "c": kVK_ANSI_C,
        "d": kVK_ANSI_D,
        "e": kVK_ANSI_E,
        "f": kVK_ANSI_F,
        "g": kVK_ANSI_G,
        "h": kVK_ANSI_H,
        "i": kVK_ANSI_I,
        "j": kVK_ANSI_J,
        "k": kVK_ANSI_K,
        "l": kVK_ANSI_L,
        "m": kVK_ANSI_M,
        "n": kVK_ANSI_N,
        "o": kVK_ANSI_O,
        "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q,
        "r": kVK_ANSI_R,
        "s": kVK_ANSI_S,
        "t": kVK_ANSI_T,
        "u": kVK_ANSI_U,
        "v": kVK_ANSI_V,
        "w": kVK_ANSI_W,
        "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0,
        "1": kVK_ANSI_1,
        "2": kVK_ANSI_2,
        "3": kVK_ANSI_3,
        "4": kVK_ANSI_4,
        "5": kVK_ANSI_5,
        "6": kVK_ANSI_6,
        "7": kVK_ANSI_7,
        "8": kVK_ANSI_8,
        "9": kVK_ANSI_9
    ]
}

private enum HotkeyConfigurationError: Error, CustomStringConvertible {
    case unsupportedKey(String)
    case unsupportedModifier(String)
    case noModifiers

    var description: String {
        switch self {
        case .unsupportedKey(let key):
            return "Unsupported hotkey key: \(key). Use A-Z or 0-9."
        case .unsupportedModifier(let modifier):
            return "Unsupported hotkey modifier: \(modifier). Use control, option, command, or shift."
        case .noModifiers:
            return "Hotkey must include at least one modifier."
        }
    }
}

private extension NSAlert {
    static func showEdgeAIError(message: String) {
        let alert = NSAlert()
        alert.messageText = "On-Device AI Engine Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private extension NSTextField {
    static func preferenceLabel(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.alignment = .right
        return label
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    var result: UInt32 = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + UInt32(scalar.value)
    }
    return result
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
