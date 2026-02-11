import Cocoa
import Foundation

struct GHAccount {
    let username: String
    let isActive: Bool
}

struct AppConfig: Codable {
    var accountColors: [String: String] = [:]
    var defaultColorHex: String = "#FFFFFF"
    var showFullUsername: Bool = true
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }

    func toHexString() -> String {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return "#FFFFFF"
        }

        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

final class ConfigManager {
    private(set) var config: AppConfig = AppConfig()
    let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folderURL = appSupport.appendingPathComponent("GHStatusToggle", isDirectory: true)
        fileURL = folderURL.appendingPathComponent("config.json")
        ensureFolderExists(folderURL)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            return
        }

        if let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func update(_ config: AppConfig) {
        self.config = config
        save()
    }

    func color(for username: String) -> NSColor {
        if let hex = config.accountColors[username], let color = NSColor(hex: hex) {
            return color
        }
        return NSColor(hex: config.defaultColorHex) ?? .white
    }

    private func ensureFolderExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

final class GitHubAuthService {
    private static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    func fetchAccounts() -> [GHAccount] {
        let result = runGH(["auth", "status", "--hostname", "github.com"])
        guard result.exitCode == 0 else {
            return []
        }

        let lines = result.stdout.components(separatedBy: .newlines)
        var seen: [String] = []
        var activeUsernames = Set<String>()
        var currentCandidate: String?

        for line in lines {
            if let username = parseLoggedInUsername(line) {
                if !seen.contains(username) {
                    seen.append(username)
                }
                currentCandidate = username
                continue
            }

            if line.localizedCaseInsensitiveContains("Active account: true"), let username = currentCandidate {
                activeUsernames.insert(username)
            }
        }

        if activeUsernames.isEmpty, let first = seen.first {
            activeUsernames.insert(first)
        }

        return seen.map { GHAccount(username: $0, isActive: activeUsernames.contains($0)) }
    }

    func switchAccount(to username: String) -> Bool {
        let result = runGH(["auth", "switch", "--hostname", "github.com", "--user", username])
        return result.exitCode == 0
    }

    private func runGH(_ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        if !currentPath.contains("/opt/homebrew/bin") && !currentPath.contains("/usr/local/bin") {
            env["PATH"] = "\(GitHubAuthService.defaultPath):\(currentPath)"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func parseLoggedInUsername(_ line: String) -> String? {
        guard let accountRange = line.range(of: " account ") else {
            return nil
        }

        let rest = line[accountRange.upperBound...]
        guard let firstToken = rest.split(separator: " ").first else {
            return nil
        }

        let username = firstToken.replacingOccurrences(of: ":", with: "")
        return username.isEmpty ? nil : username
    }
}

final class SettingsWindowController: NSWindowController {
    private let configManager: ConfigManager
    private let accounts: [GHAccount]
    private let onSave: () -> Void

    private var colorWells: [String: NSColorWell] = [:]
    private let defaultColorWell = NSColorWell(frame: .zero)
    private let fullUsernameCheckbox = NSButton(checkboxWithTitle: "Show full username in status bar", target: nil, action: nil)

    init(configManager: ConfigManager, accounts: [GHAccount], onSave: @escaping () -> Void) {
        self.configManager = configManager
        self.accounts = accounts
        self.onSave = onSave

        let rowCount = max(accounts.count, 1)
        let height = CGFloat(170 + rowCount * 36)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GH Status Toggle Settings"
        window.isReleasedWhenClosed = false

        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            container.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])

        let intro = NSTextField(labelWithString: "Assign a color to each GitHub account.")
        intro.lineBreakMode = .byWordWrapping
        intro.maximumNumberOfLines = 2
        container.addArrangedSubview(intro)

        if accounts.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No accounts found. Run `gh auth login` first.")
            emptyLabel.textColor = .secondaryLabelColor
            container.addArrangedSubview(emptyLabel)
        } else {
            for account in accounts {
                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .centerY
                row.distribution = .fill
                row.spacing = 10

                let label = NSTextField(labelWithString: account.username)
                label.font = .systemFont(ofSize: 12, weight: .medium)
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)

                let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 50, height: 24))
                colorWell.color = configManager.color(for: account.username)
                colorWells[account.username] = colorWell

                row.addArrangedSubview(label)
                row.addArrangedSubview(colorWell)
                container.addArrangedSubview(row)
            }
        }

        let defaultRow = NSStackView()
        defaultRow.orientation = .horizontal
        defaultRow.alignment = .centerY
        defaultRow.distribution = .fill
        defaultRow.spacing = 10

        let defaultLabel = NSTextField(labelWithString: "Default color")
        defaultLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        defaultColorWell.color = NSColor(hex: configManager.config.defaultColorHex) ?? .white

        defaultRow.addArrangedSubview(defaultLabel)
        defaultRow.addArrangedSubview(defaultColorWell)
        container.addArrangedSubview(defaultRow)

        fullUsernameCheckbox.state = configManager.config.showFullUsername ? .on : .off
        container.addArrangedSubview(fullUsernameCheckbox)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        buttonRow.distribution = .gravityAreas

        let openFolderButton = NSButton(title: "Open Config Folder", target: self, action: #selector(openConfigFolder))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))

        buttonRow.addArrangedSubview(openFolderButton)
        buttonRow.addArrangedSubview(NSView())
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(saveButton)
        container.addArrangedSubview(buttonRow)
    }

    @objc private func saveSettings() {
        var updated = configManager.config
        updated.defaultColorHex = defaultColorWell.color.toHexString()
        updated.showFullUsername = (fullUsernameCheckbox.state == .on)

        for (username, colorWell) in colorWells {
            updated.accountColors[username] = colorWell.color.toHexString()
        }

        configManager.update(updated)
        onSave()
        close()
    }

    @objc private func closeWindow() {
        close()
    }

    @objc private func openConfigFolder() {
        let folder = configManager.fileURL.deletingLastPathComponent()
        NSWorkspace.shared.open(folder)
    }
}

final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let authService = GitHubAuthService()
    private let configManager = ConfigManager()
    private var accounts: [GHAccount] = []
    private var refreshTimer: Timer?
    private var settingsWindowController: SettingsWindowController?

    override init() {
        super.init()
        configureStatusItem()
        refreshAccounts()
        startTimer()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemPressed(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.title = "GH ?"
    }

    private func startTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.refreshAccounts()
        }
    }

    @objc private func statusItemPressed(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleToNextAccount()
            return
        }

        switch event.type {
        case .rightMouseUp:
            presentContextMenu(with: event)
        default:
            toggleToNextAccount()
        }
    }

    @objc private func refreshAccountsAction() {
        refreshAccounts()
    }

    @objc private func openSettings() {
        let controller = SettingsWindowController(
            configManager: configManager,
            accounts: accounts
        ) { [weak self] in
            self?.refreshAccounts()
        }

        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard let username = sender.representedObject as? String else {
            return
        }

        if authService.switchAccount(to: username) {
            refreshAccounts()
        }
    }

    private func presentContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "GitHub Accounts", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        if accounts.isEmpty {
            let empty = NSMenuItem(title: "No accounts found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for account in accounts {
                let item = NSMenuItem(title: account.username, action: #selector(selectAccount(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = account.username
                item.state = account.isActive ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshAccountsAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit GH Status Toggle", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        guard let button = statusItem.button else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    private func toggleToNextAccount() {
        refreshAccounts()
        guard accounts.count > 1 else { return }

        let activeIndex = accounts.firstIndex(where: { $0.isActive }) ?? 0
        let nextIndex = (activeIndex + 1) % accounts.count
        let target = accounts[nextIndex].username

        if authService.switchAccount(to: target) {
            refreshAccounts()
        }
    }

    private func refreshAccounts() {
        accounts = authService.fetchAccounts()
        updateStatusBarLabel()
    }

    private func updateStatusBarLabel() {
        guard let button = statusItem.button else { return }

        guard let activeAccount = accounts.first(where: { $0.isActive }) ?? accounts.first else {
            button.attributedTitle = NSAttributedString(string: "GH ?")
            button.toolTip = "No GitHub accounts found. Run: gh auth login"
            return
        }

        let labelUsername = configManager.config.showFullUsername
            ? activeAccount.username
            : String(activeAccount.username.prefix(4))

        let dotColor = configManager.color(for: activeAccount.username)
        let label = "● \(labelUsername)"
        let attributed = NSMutableAttributedString(string: label)
        attributed.addAttribute(.foregroundColor, value: dotColor, range: NSRange(location: 0, length: 1))
        attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 2, length: labelUsername.count))
        attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .medium), range: NSRange(location: 0, length: label.count))

        button.attributedTitle = attributed
        button.toolTip = "Active GitHub account: \(activeAccount.username)"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
