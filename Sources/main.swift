import Cocoa
import Foundation

struct GHAccount {
    let username: String
    let isActive: Bool
}

enum UsernameDisplayMode: String, Codable, CaseIterable {
    case none
    case short
    case full

    var title: String {
        switch self {
        case .none:
            return "No username"
        case .short:
            return "Short username"
        case .full:
            return "Full username"
        }
    }
}

enum SymbolLibrary {
    static let fallback = "circle.fill"
    static let symbolNames: [String] = [
        "circle.fill",
        "person.fill",
        "person.crop.circle.fill",
        "person.2.fill",
        "person.badge.shield.checkmark.fill",
        "briefcase.fill",
        "building.2.fill",
        "desktopcomputer",
        "laptopcomputer",
        "terminal.fill",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "gearshape.fill",
        "tag.fill",
        "folder.fill",
        "star.fill",
        "flag.fill",
        "bolt.fill",
        "flame.fill",
        "leaf.fill",
        "globe.americas.fill",
        "paperplane.fill",
        "tray.full.fill",
        "shippingbox.fill"
    ]

    static func resolvedSymbol(_ proposed: String?) -> String {
        guard
            let proposed,
            !proposed.isEmpty,
            NSImage(systemSymbolName: proposed, accessibilityDescription: nil) != nil
        else {
            return fallback
        }
        return proposed
    }
}

struct AppConfig: Codable {
    var accountColors: [String: String] = [:]
    var defaultColorHex: String = "#FFFFFF"
    var usernameDisplay: UsernameDisplayMode = .full
    var accountIcons: [String: String] = [:]
    var defaultIconSymbolName: String = SymbolLibrary.fallback

    enum CodingKeys: String, CodingKey {
        case accountColors
        case defaultColorHex
        case usernameDisplay
        case accountIcons
        case defaultIconSymbolName
        case showFullUsername
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountColors = try container.decodeIfPresent([String: String].self, forKey: .accountColors) ?? [:]
        defaultColorHex = try container.decodeIfPresent(String.self, forKey: .defaultColorHex) ?? "#FFFFFF"
        accountIcons = try container.decodeIfPresent([String: String].self, forKey: .accountIcons) ?? [:]
        defaultIconSymbolName = SymbolLibrary.resolvedSymbol(
            try container.decodeIfPresent(String.self, forKey: .defaultIconSymbolName)
        )

        if let display = try container.decodeIfPresent(UsernameDisplayMode.self, forKey: .usernameDisplay) {
            usernameDisplay = display
        } else {
            let legacyFull = try container.decodeIfPresent(Bool.self, forKey: .showFullUsername) ?? true
            usernameDisplay = legacyFull ? .full : .short
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountColors, forKey: .accountColors)
        try container.encode(defaultColorHex, forKey: .defaultColorHex)
        try container.encode(usernameDisplay, forKey: .usernameDisplay)
        try container.encode(accountIcons, forKey: .accountIcons)
        try container.encode(defaultIconSymbolName, forKey: .defaultIconSymbolName)
    }
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

    func iconSymbol(for username: String) -> String {
        if let symbol = config.accountIcons[username] {
            return SymbolLibrary.resolvedSymbol(symbol)
        }
        return SymbolLibrary.resolvedSymbol(config.defaultIconSymbolName)
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
    private var iconPickers: [String: NSPopUpButton] = [:]
    private let defaultColorWell = NSColorWell(frame: .zero)
    private let defaultIconPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let usernameDisplayPicker = NSPopUpButton(frame: .zero, pullsDown: false)

    private let accountColumnWidth: CGFloat = 170
    private let iconColumnWidth: CGFloat = 260
    private let colorColumnWidth: CGFloat = 54
    private let rowSpacing: CGFloat = 10
    private let introBottomSpacing: CGFloat = 14
    private let sectionSpacing: CGFloat = 18
    private let footerTopSpacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 20
    private let topPadding: CGFloat = 24
    private let bottomPadding: CGFloat = 12

    init(configManager: ConfigManager, accounts: [GHAccount], onSave: @escaping () -> Void) {
        self.configManager = configManager
        self.accounts = accounts
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GH Status Toggle Settings"
        window.isReleasedWhenClosed = false

        super.init(window: window)
        buildUI()
        sizeWindowToContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = rowSpacing
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: topPadding),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -bottomPadding)
        ])

        let intro = NSTextField(labelWithString: "Assign a color and icon to each GitHub account.")
        intro.lineBreakMode = .byWordWrapping
        intro.maximumNumberOfLines = 2
        container.addArrangedSubview(intro)
        container.addArrangedSubview(makeVerticalSpacer(height: introBottomSpacing))

        let headerRow = makeSettingsRow()
        headerRow.addArrangedSubview(makeColumnHeader("Account", width: accountColumnWidth))
        headerRow.addArrangedSubview(makeColumnHeader("Icon", width: iconColumnWidth))
        headerRow.addArrangedSubview(makeColumnHeader("Color", width: colorColumnWidth))
        container.addArrangedSubview(headerRow)

        if accounts.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No accounts found. Run `gh auth login` first.")
            emptyLabel.textColor = .secondaryLabelColor
            container.addArrangedSubview(emptyLabel)
        } else {
            for account in accounts {
                let row = makeSettingsRow()
                let label = makeAccountLabel(account.username, width: accountColumnWidth)

                let iconPicker = makeSymbolPicker(selectedSymbolName: configManager.iconSymbol(for: account.username))
                constrainWidth(iconPicker, iconColumnWidth)
                iconPickers[account.username] = iconPicker

                let colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 50, height: 24))
                colorWell.color = configManager.color(for: account.username)
                constrainWidth(colorWell, colorColumnWidth)
                colorWells[account.username] = colorWell

                row.addArrangedSubview(label)
                row.addArrangedSubview(iconPicker)
                row.addArrangedSubview(colorWell)
                container.addArrangedSubview(row)
            }
        }

        container.addArrangedSubview(makeVerticalSpacer(height: sectionSpacing))
        let defaultLabel = NSTextField(labelWithString: "Default appearance")
        defaultLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        container.addArrangedSubview(defaultLabel)

        let defaultStyleRow = makeSettingsRow()
        let defaultIconLabel = makeAccountLabel("Default", width: accountColumnWidth)

        let defaultSymbol = SymbolLibrary.resolvedSymbol(configManager.config.defaultIconSymbolName)
        configureSymbolPicker(defaultIconPicker, selectedSymbolName: defaultSymbol)
        constrainWidth(defaultIconPicker, iconColumnWidth)

        defaultColorWell.color = NSColor(hex: configManager.config.defaultColorHex) ?? .white
        constrainWidth(defaultColorWell, colorColumnWidth)

        defaultStyleRow.addArrangedSubview(defaultIconLabel)
        defaultStyleRow.addArrangedSubview(defaultIconPicker)
        defaultStyleRow.addArrangedSubview(defaultColorWell)
        container.addArrangedSubview(defaultStyleRow)

        let usernameDisplayRow = makeSettingsRow()
        let usernameDisplayLabel = makeAccountLabel("Username display", width: accountColumnWidth)
        configureDisplayModePicker()
        constrainWidth(usernameDisplayPicker, iconColumnWidth)
        let usernameSpacer = NSView(frame: .zero)
        constrainWidth(usernameSpacer, colorColumnWidth)
        usernameSpacer.setContentHuggingPriority(.required, for: .horizontal)

        usernameDisplayRow.addArrangedSubview(usernameDisplayLabel)
        usernameDisplayRow.addArrangedSubview(usernameDisplayPicker)
        usernameDisplayRow.addArrangedSubview(usernameSpacer)
        container.addArrangedSubview(usernameDisplayRow)
        container.addArrangedSubview(makeVerticalSpacer(height: footerTopSpacing))

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))

        buttonRow.addArrangedSubview(NSView())
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(saveButton)
        container.addArrangedSubview(buttonRow)
    }

    @objc private func saveSettings() {
        var updated = configManager.config
        updated.defaultColorHex = defaultColorWell.color.toHexString()
        updated.defaultIconSymbolName = selectedSymbolName(from: defaultIconPicker)
        updated.usernameDisplay = selectedDisplayMode()

        for (username, colorWell) in colorWells {
            updated.accountColors[username] = colorWell.color.toHexString()
        }
        for (username, iconPicker) in iconPickers {
            updated.accountIcons[username] = selectedSymbolName(from: iconPicker)
        }

        configManager.update(updated)
        onSave()
        close()
    }

    @objc private func closeWindow() {
        close()
    }

    private func configureDisplayModePicker() {
        usernameDisplayPicker.removeAllItems()

        for mode in UsernameDisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: nil, keyEquivalent: "")
            item.representedObject = mode.rawValue
            usernameDisplayPicker.menu?.addItem(item)
        }

        if let selected = usernameDisplayPicker.itemArray.first(where: {
            ($0.representedObject as? String) == configManager.config.usernameDisplay.rawValue
        }) {
            usernameDisplayPicker.select(selected)
        } else {
            usernameDisplayPicker.selectItem(at: 0)
        }
    }

    private func selectedDisplayMode() -> UsernameDisplayMode {
        guard
            let rawValue = usernameDisplayPicker.selectedItem?.representedObject as? String,
            let mode = UsernameDisplayMode(rawValue: rawValue)
        else {
            return .full
        }
        return mode
    }

    private func makeSymbolPicker(selectedSymbolName: String) -> NSPopUpButton {
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        configureSymbolPicker(picker, selectedSymbolName: selectedSymbolName)
        return picker
    }

    private func configureSymbolPicker(_ picker: NSPopUpButton, selectedSymbolName: String) {
        picker.removeAllItems()

        for symbolName in SymbolLibrary.symbolNames {
            let item = NSMenuItem(title: symbolName, action: nil, keyEquivalent: "")
            item.representedObject = symbolName
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)) {
                item.image = image
            }
            picker.menu?.addItem(item)
        }

        let resolved = SymbolLibrary.resolvedSymbol(selectedSymbolName)
        if let selected = picker.itemArray.first(where: { ($0.representedObject as? String) == resolved }) {
            picker.select(selected)
        } else {
            picker.selectItem(at: 0)
        }
    }

    private func selectedSymbolName(from picker: NSPopUpButton) -> String {
        SymbolLibrary.resolvedSymbol(picker.selectedItem?.representedObject as? String)
    }

    private func makeSettingsRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        return row
    }

    private func makeColumnHeader(_ title: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        constrainWidth(label, width)
        return label
    }

    private func makeAccountLabel(_ title: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.setContentHuggingPriority(.required, for: .horizontal)
        constrainWidth(label, width)
        return label
    }

    private func constrainWidth(_ view: NSView, _ width: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func makeVerticalSpacer(height: CGFloat) -> NSView {
        let spacer = NSView(frame: .zero)
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }

    private func sizeWindowToContent() {
        guard let window = window, let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let targetHeight = max(320, contentView.fittingSize.height)
        window.setContentSize(NSSize(width: 620, height: targetHeight))
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
        button.imagePosition = .imageLeading
        button.image = statusImage(symbolName: "questionmark.circle", tintColor: .secondaryLabelColor)
        button.attributedTitle = NSAttributedString(string: " GH ?")
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
        titleItem.image = menuImage(symbolName: "person.2.fill")
        menu.addItem(titleItem)
        menu.addItem(.separator())

        if accounts.isEmpty {
            let empty = NSMenuItem(title: "No accounts found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.image = menuImage(symbolName: "exclamationmark.triangle")
            menu.addItem(empty)
        } else {
            for account in accounts {
                let isActive = account.isActive
                let title = isActive ? "\(account.username) (Active)" : account.username
                let item = NSMenuItem(title: title, action: #selector(selectAccount(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = account.username
                let tintColor = isActive ? configManager.color(for: account.username) : nil
                item.image = menuImage(symbolName: configManager.iconSymbol(for: account.username), tintColor: tintColor)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshAccountsAction), keyEquivalent: "r")
        refresh.target = self
        refresh.image = menuImage(symbolName: "arrow.clockwise")
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = menuImage(symbolName: "gearshape")
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit GH Status Toggle", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.image = menuImage(symbolName: "power")
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
            button.image = statusImage(symbolName: "questionmark.circle", tintColor: .secondaryLabelColor)
            button.attributedTitle = NSAttributedString(string: " GH ?")
            statusItem.length = NSStatusItem.variableLength
            button.toolTip = "No GitHub accounts found. Run: gh auth login"
            return
        }

        let iconColor = configManager.color(for: activeAccount.username)
        button.image = statusImage(symbolName: configManager.iconSymbol(for: activeAccount.username), tintColor: iconColor)

        let usernameLabel = usernameText(for: activeAccount.username)
        if usernameLabel.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
            statusItem.length = NSStatusItem.squareLength
        } else {
            let label = " \(usernameLabel)"
            let attributed = NSMutableAttributedString(string: label)
            attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: label.count))
            attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .medium), range: NSRange(location: 0, length: label.count))
            button.attributedTitle = attributed
            statusItem.length = NSStatusItem.variableLength
        }

        button.imagePosition = .imageLeading
        button.toolTip = "Active GitHub account: \(activeAccount.username)"
    }

    private func usernameText(for username: String) -> String {
        switch configManager.config.usernameDisplay {
        case .none:
            return ""
        case .short:
            return String(username.prefix(4))
        case .full:
            return username
        }
    }

    private func statusImage(symbolName: String, tintColor: NSColor) -> NSImage? {
        symbolImage(symbolName: symbolName, pointSize: 13, weight: .semibold, tintColor: tintColor)
    }

    private func menuImage(symbolName: String, tintColor: NSColor? = nil) -> NSImage? {
        symbolImage(symbolName: symbolName, pointSize: 13, weight: .regular, tintColor: tintColor)
    }

    private func symbolImage(
        symbolName: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        tintColor: NSColor?
    ) -> NSImage? {
        let resolved = SymbolLibrary.resolvedSymbol(symbolName)
        guard let symbol = NSImage(systemSymbolName: resolved, accessibilityDescription: "Active GitHub account icon")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
        else {
            return nil
        }

        guard let tintColor else {
            symbol.isTemplate = true
            return symbol
        }

        let rect = NSRect(origin: .zero, size: symbol.size)
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        tintColor.setFill()
        rect.fill()
        symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
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
