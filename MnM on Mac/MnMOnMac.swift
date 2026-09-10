//
//  MnMOnMac.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import AppKit

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private let hiddenSetupDotAttribute = NSAttributedString.Key("MnMHiddenSetupDot")

final class CoverImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let frame = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                           width: size.width, height: size.height)
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

final class PrimaryActionCell: NSButtonCell {
    private let accentColor = NSColor(calibratedRed: 0.94, green: 0.31, blue: 0.035, alpha: 1)

    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        let color = isEnabled ? (isHighlighted ? accentColor.blended(withFraction: 0.18, of: .black)! : accentColor) : .controlBackgroundColor
        color.setFill()
        NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).fill()
    }
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let styled = NSMutableAttributedString(attributedString: title)
        styled.addAttributes([.foregroundColor: isEnabled ? NSColor.white : NSColor.secondaryLabelColor,
                              .font: NSFont.systemFont(ofSize: 20, weight: .semibold)], range: NSRange(location: 0, length: styled.length))
        styled.enumerateAttribute(hiddenSetupDotAttribute, in: NSRange(location: 0, length: styled.length)) { value, range, _ in
            if value != nil { styled.addAttribute(.foregroundColor, value: NSColor.clear, range: range) }
        }
        return super.drawTitle(styled, withFrame: frame, in: controlView)
    }
}

final class GhostActionCell: NSButtonCell {
    private let tintColor: NSColor

    init(textCell: String, tintColor: NSColor = .labelColor) {
        self.tintColor = tintColor
        super.init(textCell: textCell)
    }

    required init(coder: NSCoder) {
        tintColor = .labelColor
        super.init(coder: coder)
    }

    override var isHighlighted: Bool {
        get { false }
        set { }
    }

    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        NSColor.white.withAlphaComponent(0.12).setStroke()
        NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        rect.insetBy(dx: 12, dy: 0)
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let styled = NSMutableAttributedString(attributedString: title)
        styled.addAttributes([
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ], range: NSRange(location: 0, length: styled.length))
        return super.drawTitle(styled, withFrame: frame, in: controlView)
    }
}

final class HeroCardView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.shadowOffset = NSSize(width: 0, height: -2)

        let tintView = NSView()
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        tintView.layer?.cornerRadius = 11
        tintView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tintView)
        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintView.topAnchor.constraint(equalTo: topAnchor),
            tintView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class MaintenanceCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.04).cgColor
    }

    required init?(coder: NSCoder) { nil }
}

struct HelperResult {
    let code: Int32
    let text: String
}

func runHelper(_ arguments: [String]) -> HelperResult {
    guard let helper = Bundle.main.url(forResource: "mnm-launcher", withExtension: "sh") else {
        return HelperResult(code: 1, text: "The app's launcher helper is missing. Restore the complete app.")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [helper.path] + arguments
    var environment = ProcessInfo.processInfo.environment
    environment["MNM_SUPPORT_DIR"] = AppStorage.directory.path
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return HelperResult(code: process.terminationStatus,
                            text: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
        return HelperResult(code: 1, text: "The launcher helper could not start: \(error.localizedDescription)")
    }
}

@main
enum MnMOnMac {
    static func main() {
        if CommandLine.arguments.contains("--check") {
            print(WineRuntime.readiness)
            return
        }
        if CommandLine.arguments.contains("--check-launcher") {
            let result = runHelper(["native-path"])
            print(result.text)
            exit(result.code)
        }
        let application = NSApplication.shared
        let delegate = LauncherDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class LauncherDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let updatesURL = URL(string: "https://monstersandmemories.com/updates")!
    private static let masterUserAgreementURL = URL(string: "https://account.monstersandmemories.com/policy/mau")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/seathasky/MnM-on-Mac/releases/latest")!
    private static let accentColor = NSColor(calibratedRed: 0.94, green: 0.31, blue: 0.035, alpha: 1)
    private static let completedInitialSetupKey = "MnMCompletedInitialSetup"
    private static let hideWelcomeKey = "MnMHideWelcomeExplanation"
    private static let graphicsBackendKey = "MnMGraphicsBackend"
    private static let confirmedDXVKKey = "MnMConfirmedDXVKRisk"
    private static let confirmedKosmicKrispKey = "MnMConfirmedKosmicKrispRisk"
    private static let confirmedD3DMetalKey = "MnMConfirmedD3DMetalLicense"
    private static let metalPerformanceHUDKey = "MnMMetalPerformanceHUD"
    private static let dxvkPerformanceHUDKey = "MnMDXVKPerformanceHUD"
    private static let kosmicKrispPerformanceHUDKey = "MnMKosmicKrispPerformanceHUD"
    private static let d3dMetalPerformanceHUDKey = "MnMD3DMetalPerformanceHUD"
    private static let metalFXUpscalingKey = "MnMMetalFXUpscaling"
    private static let gameModeKey = "MnMGameMode"
    private static let msyncEnabledKey = "MnMMsyncEnabled"
    private static let terminalLogKey = "MnMTerminalLog"
    private var window: NSWindow!
    private let statusLabel = NSTextField(wrappingLabelWithString: "Checking your game…")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var errorGroup: NSStackView!
    private var playButton: NSButton!
    private var updateButton: NSButton!
    private var reauthenticateButton: NSButton!
    private var folderButton: NSButton!
    private var setupLogButton: NSButton!
    private var fileActions: NSStackView!
    private var accountActions: NSStackView!
    private var launcherSectionLabel: NSTextField!
    private var setupInfo: NSStackView!
    private var setupInfoTitle: NSTextField!
    private var setupInfoBody: NSTextField!
    private var errorGroupHeightConstraint: NSLayoutConstraint!
    private var heroHeightConstraint: NSLayoutConstraint!
    private var graphicsBackendRow: NSStackView!
    private var graphicsBackendButton: NSPopUpButton!
    private var officialSectionLabel: NSTextField!
    private var sectionDivider: NSView!
    private var maintenanceCard: NSView!
    private var thirdPartyButton: NSButton!
    private var versionButton: NSButton!
    private var hudButton: NSButton!
    private var availableReleaseURL: URL?
    private var availableAssetURL: URL?
    private var updatePromptShown = false
    private var state = ""
    private var busy = false
    private var patcherProcess: Process?
    private var closePatcherAfterInitialSetup = false
    private var patcherReadyChecks = 0
    private var expectedPatcherTermination = false
    private var lastPatcherFailure: String?
    private var gameProcess: Process?
    private var storageFailure: String?
    private var refreshTimer: Timer?
    private var setupAnimationTimer: Timer?
    private var setupAnimationFrame = 1
    private var lastGameStatusUpdate: TimeInterval = 0
    private var thirdPartyWindow: NSWindow?
    private let gameModeController = GameModeController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        do {
            if AppStorage.requiresMigration {
                let otherLaunchers = NSRunningApplication.runningApplications(withBundleIdentifier: WineRuntime.bundleIdentifier)
                    .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
                let patcherIsOpen = NSRunningApplication.runningApplications(withBundleIdentifier: NativePatcherInstaller.bundleID)
                    .contains { !$0.isTerminated }
                guard !otherLaunchers, !patcherIsOpen else {
                    throw PatcherSetupError.message("Quit the older launcher and MnM patcher, then reopen this app to rename its data folder safely.")
                }
            }
            try AppStorage.prepare()
        } catch { storageFailure = error.localizedDescription }
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !UserDefaults.standard.bool(forKey: Self.hideWelcomeKey) {
            DispatchQueue.main.async { [weak self] in self?.showWelcomeExplanation() }
        }
        checkForAppUpdate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func showWelcomeExplanation() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "How MnM on Mac Works"
        alert.informativeText = "MnM on Mac sets up a self-contained Windows environment so the Windows version of Monsters & Memories can run on your Apple silicon Mac. During initial setup, it downloads Wine and the required support files, then opens the official Monsters & Memories launcher so you can sign in and install the game.\n\nAfter setup, MnM on Mac becomes your main launcher. Play starts the game directly using your saved official login session. The official launcher is only needed when you want to log in again, install an update, or repair the game. Everything stays inside MnM on Mac’s data folder, so CrossOver is not required."
        alert.addButton(withTitle: "Continue")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 24))
        let neverShowAgain = NSButton(checkboxWithTitle: "Never show again", target: nil, action: nil)
        neverShowAgain.sizeToFit()
        neverShowAgain.frame.origin = NSPoint(x: accessory.bounds.width - neverShowAgain.frame.width, y: 2)
        accessory.addSubview(neverShowAgain)
        alert.accessoryView = accessory

        alert.beginSheetModal(for: window) { _ in
            if neverShowAgain.state == .on {
                UserDefaults.standard.set(true, forKey: Self.hideWelcomeKey)
            }
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        let topItem = NSMenuItem()
        menu.addItem(topItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MnM on Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        topItem.submenu = appMenu
        let toolsItem = NSMenuItem()
        let toolsMenu = NSMenu(title: "Tools")
        toolsMenu.addItem(withTitle: "Open MnM Install Directory", action: #selector(openInstallDirectory), keyEquivalent: "").target = self
        toolsMenu.addItem(withTitle: "Choose Game Folder…", action: #selector(chooseFolder), keyEquivalent: "").target = self
        toolsMenu.addItem(withTitle: "Open Setup Log", action: #selector(openSetupLog), keyEquivalent: "").target = self
        toolsMenu.addItem(NSMenuItem.separator())
        toolsMenu.addItem(withTitle: "Re-authenticate…", action: #selector(reauthenticate), keyEquivalent: "").target = self
        toolsItem.submenu = toolsMenu
        menu.addItem(toolsItem)
        NSApp.mainMenu = menu
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 390),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "MnM on Mac (Beta)"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 900, height: 380)
        window.center()

        let bundledIcon = Bundle.main.url(forResource: "mnm", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
        if let bundledIcon { NSApp.applicationIconImage = bundledIcon }

        let icon = NSImageView()
        icon.image = bundledIcon ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let title = NSTextField(labelWithString: "MnM on Mac (Beta)")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Community launcher")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let identityText = NSStackView(views: [title, subtitle])
        identityText.orientation = .vertical
        identityText.alignment = .leading
        identityText.spacing = 2
        let identity = NSStackView(views: [icon, identityText])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 14

        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.alignment = .left
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .left
        detailLabel.preferredMaxLayoutWidth = 300
        detailLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.heightAnchor.constraint(equalToConstant: 34).isActive = true
        errorGroup = NSStackView(views: [statusLabel, detailLabel])
        errorGroup.orientation = .vertical
        errorGroup.alignment = .leading
        errorGroup.spacing = 5
        statusLabel.isHidden = true
        detailLabel.isHidden = true
        errorGroup.isHidden = true
        errorGroupHeightConstraint = errorGroup.heightAnchor.constraint(equalToConstant: 0)
        errorGroupHeightConstraint.isActive = true

        let graphicsBackendLabel = NSTextField(labelWithString: "Graphics")
        graphicsBackendLabel.font = .systemFont(ofSize: 12, weight: .medium)
        graphicsBackendLabel.setContentHuggingPriority(.required, for: .horizontal)
        graphicsBackendLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
        graphicsBackendButton = NSPopUpButton(frame: .zero, pullsDown: false)
        graphicsBackendButton.addItem(withTitle: "D3DMetal (Recommended)")
        graphicsBackendButton.addItem(withTitle: "DXMT")
        graphicsBackendButton.addItem(withTitle: "DXVK (Experimental)")
        switch selectedGraphicsBackend {
        case .metal: graphicsBackendButton.selectItem(at: 1)
        case .dxvk: graphicsBackendButton.selectItem(at: 2)
        case .kosmicKrisp: graphicsBackendButton.selectItem(at: 0)
        case .d3dMetal: graphicsBackendButton.selectItem(at: 0)
        }
        graphicsBackendButton.target = self
        graphicsBackendButton.action = #selector(graphicsBackendChanged)
        graphicsBackendButton.toolTip = "D3DMetal is recommended. Graphics options download on first use and use separate Windows environments."
        graphicsBackendButton.setAccessibilityLabel("Graphics backend")
        graphicsBackendButton.setAccessibilityHelp("Choose the graphics translation used to launch the game.")
        graphicsBackendButton.controlSize = .regular
        graphicsBackendButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        graphicsBackendButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        hudButton = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Performance HUD settings")!,
                             target: self, action: #selector(showPerformanceHUDMenu))
        hudButton.isBordered = false
        hudButton.imagePosition = .imageOnly
        updatePerformanceHUDButtonAppearance()
        hudButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        hudButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        graphicsBackendRow = NSStackView(views: [graphicsBackendLabel, graphicsBackendButton, hudButton])
        graphicsBackendRow.orientation = .horizontal
        graphicsBackendRow.alignment = .centerY
        graphicsBackendRow.distribution = .fill
        graphicsBackendRow.spacing = 8
        graphicsBackendRow.widthAnchor.constraint(equalToConstant: 300).isActive = true
        graphicsBackendRow.heightAnchor.constraint(equalToConstant: 26).isActive = true
        graphicsBackendRow.isHidden = true

        playButton = NSButton(title: "Play", target: self, action: #selector(play))
        playButton.cell = PrimaryActionCell(textCell: "Play")
        playButton.setButtonType(.momentaryPushIn)
        playButton.isBordered = true
        playButton.alignment = .center
        playButton.bezelStyle = .regularSquare
        playButton.font = .systemFont(ofSize: 20, weight: .semibold)
        playButton.controlSize = .large
        playButton.target = self
        playButton.action = #selector(play)
        playButton.keyEquivalent = "\r"
        playButton.widthAnchor.constraint(equalToConstant: 300).isActive = true
        playButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        updateButton = NSButton(title: "Install / Update / Login", target: self, action: #selector(update))
        updateButton.cell = GhostActionCell(textCell: "Install / Update / Login")
        updateButton.isBordered = true
        updateButton.bezelStyle = .regularSquare
        updateButton.controlSize = .large
        updateButton.target = self
        updateButton.action = #selector(update)
        updateButton.widthAnchor.constraint(equalToConstant: 300).isActive = true
        updateButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        reauthenticateButton = NSButton(title: "Re-authenticate…", target: self, action: #selector(reauthenticate))
        reauthenticateButton.cell = GhostActionCell(textCell: "Re-authenticate…")
        reauthenticateButton.isBordered = true
        reauthenticateButton.bezelStyle = .regularSquare
        reauthenticateButton.controlSize = .large
        reauthenticateButton.target = self
        reauthenticateButton.action = #selector(reauthenticate)
        reauthenticateButton.widthAnchor.constraint(equalToConstant: 300).isActive = true
        reauthenticateButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        accountActions = NSStackView(views: [updateButton, reauthenticateButton])
        accountActions.orientation = .vertical
        accountActions.alignment = .leading
        accountActions.spacing = 6
        accountActions.widthAnchor.constraint(equalToConstant: 300).isActive = true

        launcherSectionLabel = NSTextField(labelWithString: "Initial Setup")
        launcherSectionLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        launcherSectionLabel.textColor = Self.accentColor
        launcherSectionLabel.heightAnchor.constraint(equalToConstant: 14).isActive = true
        launcherSectionLabel.isHidden = true

        setupInfoTitle = NSTextField(labelWithString: "Why Wine is needed")
        setupInfoTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        setupInfoBody = NSTextField(wrappingLabelWithString: "Monsters & Memories is built for Windows. Wine lets it run on your Mac inside a private environment, with no separate CrossOver installation required.")
        setupInfoBody.font = .systemFont(ofSize: 11)
        setupInfoBody.textColor = .secondaryLabelColor
        setupInfoBody.preferredMaxLayoutWidth = 300
        setupInfoBody.widthAnchor.constraint(equalToConstant: 300).isActive = true
        setupInfo = NSStackView(views: [setupInfoTitle, setupInfoBody])
        setupInfo.orientation = .vertical
        setupInfo.alignment = .leading
        setupInfo.spacing = 6
        setupInfo.isHidden = true
        let labelColor = NSColor.white.withAlphaComponent(0.4)
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .bold)
        let italicLabelFont = NSFontManager.shared.convert(labelFont, toHaveTrait: .italicFontMask)
        let labelText = NSMutableAttributedString(string: "Official MnM Launcher", attributes: [
            .font: labelFont,
            .foregroundColor: labelColor
        ])
        let italicText = NSAttributedString(string: " (used for setup only)", attributes: [
            .font: italicLabelFont,
            .foregroundColor: NSColor.systemRed.withAlphaComponent(0.6)
        ])
        labelText.append(italicText)
        officialSectionLabel = NSTextField(labelWithAttributedString: labelText)
        sectionDivider = NSView()
        sectionDivider.wantsLayer = true
        sectionDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        sectionDivider.widthAnchor.constraint(equalToConstant: 300).isActive = true
        sectionDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        folderButton = NSButton(title: "Choose Game Folder…", target: self, action: #selector(chooseFolder))
        folderButton.bezelStyle = .rounded
        folderButton.font = .systemFont(ofSize: 11)
        let installDirectoryButton = NSButton(title: "Game Files", target: self, action: #selector(openInstallDirectory))
        installDirectoryButton.bezelStyle = .rounded
        installDirectoryButton.font = .systemFont(ofSize: 11)
        fileActions = NSStackView(views: [installDirectoryButton, folderButton])
        fileActions.orientation = .horizontal
        fileActions.distribution = .fillEqually
        fileActions.spacing = 8
        fileActions.widthAnchor.constraint(equalToConstant: 300).isActive = true
        fileActions.heightAnchor.constraint(equalToConstant: 30).isActive = true

        setupLogButton = NSButton(title: "Open Setup Log", target: self, action: #selector(openSetupLog))
        setupLogButton.bezelStyle = .inline
        setupLogButton.font = .systemFont(ofSize: 12)
        setupLogButton.isHidden = true

        thirdPartyButton = NSButton(title: "About", target: self, action: #selector(showThirdPartySoftware))
        thirdPartyButton.isBordered = false
        thirdPartyButton.attributedTitle = NSAttributedString(
            string: "About",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: Self.accentColor,
                         .underlineStyle: NSUnderlineStyle.single.rawValue])
        thirdPartyButton.alignment = .center
        thirdPartyButton.setAccessibilityLabel("About MnM on Mac and third-party software")

        let legalButton = NSButton(title: "Legal", target: self, action: #selector(showLegalExplanation))
        legalButton.isBordered = false
        legalButton.attributedTitle = NSAttributedString(
            string: "Legal",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: Self.accentColor,
                         .underlineStyle: NSUnderlineStyle.single.rawValue])
        legalButton.setAccessibilityLabel("Legal and compatibility information")

        versionButton = NSButton(title: "", target: nil, action: nil)
        versionButton.isBordered = false
        versionButton.alignment = .left
        versionButton.setAccessibilityLabel("MnM on Mac version")
        showInstalledVersion()

        let footerDivider = NSView()
        footerDivider.wantsLayer = true
        footerDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        footerDivider.widthAnchor.constraint(equalToConstant: 332).isActive = true
        footerDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        versionButton.setContentHuggingPriority(.required, for: .horizontal)
        thirdPartyButton.setContentHuggingPriority(.required, for: .horizontal)
        legalButton.setContentHuggingPriority(.required, for: .horizontal)
        thirdPartyButton.alignment = .center
        legalButton.alignment = .right
        let footerRightLinks = NSStackView(views: [thirdPartyButton, legalButton])
        footerRightLinks.orientation = .horizontal
        footerRightLinks.alignment = .centerY
        footerRightLinks.spacing = 12
        let footerLinks = NSView()
        for view in [versionButton!, footerRightLinks] {
            view.translatesAutoresizingMaskIntoConstraints = false
            footerLinks.addSubview(view)
        }
        setupLogButton.translatesAutoresizingMaskIntoConstraints = false
        footerLinks.addSubview(setupLogButton)
        footerLinks.widthAnchor.constraint(equalToConstant: 332).isActive = true
        footerLinks.heightAnchor.constraint(equalToConstant: 22).isActive = true
        NSLayoutConstraint.activate([
            versionButton.leadingAnchor.constraint(equalTo: footerLinks.leadingAnchor),
            versionButton.centerYAnchor.constraint(equalTo: footerLinks.centerYAnchor),
            setupLogButton.centerXAnchor.constraint(equalTo: footerLinks.centerXAnchor),
            setupLogButton.centerYAnchor.constraint(equalTo: footerLinks.centerYAnchor),
            footerRightLinks.trailingAnchor.constraint(equalTo: footerLinks.trailingAnchor),
            footerRightLinks.centerYAnchor.constraint(equalTo: footerLinks.centerYAnchor)
        ])

        let heroCard = HeroCardView()
        heroCard.translatesAutoresizingMaskIntoConstraints = false
        heroCard.widthAnchor.constraint(equalToConstant: 332).isActive = true
        heroCard.setContentHuggingPriority(.required, for: .vertical)
        heroCard.setContentCompressionResistancePriority(.required, for: .vertical)
        // Keep the hero compact. The error group is the only conditional content
        // between the primary action and the file controls.
        heroHeightConstraint = heroCard.heightAnchor.constraint(equalToConstant: 212)
        heroHeightConstraint.isActive = true
        let heroViews: [NSView] = [identity, errorGroup, playButton, fileActions, graphicsBackendRow]
        for view in heroViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            heroCard.addSubview(view)
        }
        NSLayoutConstraint.activate([
            identity.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 16),
            identity.trailingAnchor.constraint(lessThanOrEqualTo: heroCard.trailingAnchor, constant: -16),
            identity.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 14),

            // Keep Play, Set Up Wine, and Show Official Launcher in one fixed slot.
            playButton.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 16),
            playButton.topAnchor.constraint(equalTo: identity.bottomAnchor, constant: 10),

            errorGroup.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 16),
            errorGroup.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -16),
            errorGroup.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 6),

            fileActions.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 16),
            fileActions.topAnchor.constraint(equalTo: errorGroup.bottomAnchor, constant: 6),

            graphicsBackendRow.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 16),
            graphicsBackendRow.topAnchor.constraint(equalTo: fileActions.bottomAnchor, constant: 6)
        ])

        let maintenanceContent = NSStackView(views: [officialSectionLabel, accountActions])
        maintenanceContent.orientation = .vertical
        maintenanceContent.alignment = .leading
        maintenanceContent.spacing = 7
        maintenanceContent.setCustomSpacing(3, after: officialSectionLabel)
        maintenanceContent.setCustomSpacing(10, after: accountActions)

        maintenanceCard = MaintenanceCardView()
        maintenanceCard.widthAnchor.constraint(equalToConstant: 332).isActive = true
        maintenanceCard.setContentHuggingPriority(.required, for: .vertical)
        maintenanceCard.setContentCompressionResistancePriority(.required, for: .vertical)
        maintenanceCard.translatesAutoresizingMaskIntoConstraints = false
        maintenanceContent.translatesAutoresizingMaskIntoConstraints = false
        maintenanceCard.addSubview(maintenanceContent)
        NSLayoutConstraint.activate([
            maintenanceContent.leadingAnchor.constraint(equalTo: maintenanceCard.leadingAnchor, constant: 16),
            maintenanceContent.trailingAnchor.constraint(equalTo: maintenanceCard.trailingAnchor, constant: -16),
            maintenanceContent.topAnchor.constraint(equalTo: maintenanceCard.topAnchor, constant: 12),
            maintenanceContent.bottomAnchor.constraint(equalTo: maintenanceCard.bottomAnchor, constant: -12)
        ])

        let controls = NSStackView(views: [heroCard, maintenanceCard, footerDivider, footerLinks])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 16
        controls.setCustomSpacing(8, after: heroCard)
        controls.setCustomSpacing(8, after: maintenanceCard)
        controls.setCustomSpacing(8, after: footerDivider)
        controls.translatesAutoresizingMaskIntoConstraints = false

        let controlsPanel = NSView()
        controlsPanel.wantsLayer = true
        controlsPanel.layer?.backgroundColor = NSColor(calibratedWhite: 0.105, alpha: 1).cgColor
        controlsPanel.translatesAutoresizingMaskIntoConstraints = false
        controlsPanel.addSubview(controls)

        let panelDivider = NSView()
        panelDivider.wantsLayer = true
        panelDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        panelDivider.translatesAutoresizingMaskIntoConstraints = false
        controlsPanel.addSubview(panelDivider)

        let updatesLink = NSButton(title: "Official Updates ↗", target: self, action: #selector(openUpdatesWebsite))
        updatesLink.isBordered = false
        updatesLink.attributedTitle = NSAttributedString(
            string: "Official Updates ↗",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                         .foregroundColor: Self.accentColor,
                         .underlineStyle: NSUnderlineStyle.single.rawValue])
        updatesLink.translatesAutoresizingMaskIntoConstraints = false

        let backgroundImage = NSImage(contentsOf: Bundle.main.url(forResource: "GelatenousCube", withExtension: "png")!)!
        let backgroundImageView = CoverImageView(image: backgroundImage)
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false

        let websitePanel = NSView()
        websitePanel.wantsLayer = true
        websitePanel.layer?.backgroundColor = NSColor(calibratedWhite: 0.105, alpha: 1).cgColor
        websitePanel.translatesAutoresizingMaskIntoConstraints = false
        websitePanel.addSubview(backgroundImageView)
        websitePanel.addSubview(updatesLink)

        guard let contentView = window.contentView else { return }
        contentView.addSubview(websitePanel)
        contentView.addSubview(controlsPanel)
        NSLayoutConstraint.activate([
            websitePanel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            websitePanel.topAnchor.constraint(equalTo: contentView.topAnchor),
            websitePanel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            websitePanel.trailingAnchor.constraint(equalTo: controlsPanel.leadingAnchor),
            websitePanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 540),

            controlsPanel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            controlsPanel.topAnchor.constraint(equalTo: contentView.topAnchor),
            controlsPanel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            controlsPanel.widthAnchor.constraint(equalToConstant: 382),

            panelDivider.leadingAnchor.constraint(equalTo: controlsPanel.leadingAnchor),
            panelDivider.topAnchor.constraint(equalTo: controlsPanel.topAnchor),
            panelDivider.bottomAnchor.constraint(equalTo: controlsPanel.bottomAnchor),
            panelDivider.widthAnchor.constraint(equalToConstant: 1),

            backgroundImageView.leadingAnchor.constraint(equalTo: websitePanel.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: websitePanel.trailingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: websitePanel.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: websitePanel.bottomAnchor),

            updatesLink.leadingAnchor.constraint(equalTo: websitePanel.leadingAnchor, constant: 16),
            updatesLink.bottomAnchor.constraint(equalTo: websitePanel.bottomAnchor, constant: -12),

            controls.leadingAnchor.constraint(equalTo: controlsPanel.leadingAnchor, constant: 25),
            controls.trailingAnchor.constraint(equalTo: controlsPanel.trailingAnchor, constant: -25),
            controls.topAnchor.constraint(equalTo: controlsPanel.topAnchor, constant: 16),
            controls.bottomAnchor.constraint(equalTo: controlsPanel.bottomAnchor, constant: -12)
        ])
    }

    @objc private func openUpdatesWebsite() {
        NSWorkspace.shared.open(Self.updatesURL)
    }

    private func installedAppVersion() -> String {
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["MNM_TEST_APP_VERSION"],
           normalizedVersion(override) != nil {
            return override
        }
#endif
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.4"
    }

    private func normalizedVersion(_ value: String) -> [Int]? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        text = String(text.split(separator: "-", maxSplits: 1).first ?? "")
        let values = text.split(separator: ".").map { Int($0) }
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }
    }

    private func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        guard var candidateParts = normalizedVersion(candidate), var currentParts = normalizedVersion(current) else { return false }
        let count = max(candidateParts.count, currentParts.count)
        candidateParts += Array(repeating: 0, count: count - candidateParts.count)
        currentParts += Array(repeating: 0, count: count - currentParts.count)
        return currentParts.lexicographicallyPrecedes(candidateParts)
    }

    private func showInstalledVersion() {
        availableReleaseURL = nil
        versionButton.target = nil
        versionButton.action = nil
        versionButton.attributedTitle = NSAttributedString(
            string: "Version \(installedAppVersion())",
            attributes: [.font: NSFont.systemFont(ofSize: 10),
                         .foregroundColor: NSColor.secondaryLabelColor])
    }

    private func checkForAppUpdate() {
        let currentVersion = installedAppVersion()
        var request = URLRequest(url: Self.latestReleaseAPIURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MnM-on-Mac/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200,
                  let data else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                      release.htmlURL.scheme == "https",
                      release.htmlURL.host == "github.com",
                      self.isNewerVersion(release.tagName, than: currentVersion) else { return }
                let version = release.tagName.lowercased().hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                self.availableAssetURL = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })?.browserDownloadURL
                self.availableReleaseURL = release.htmlURL
                self.versionButton.target = self
                self.versionButton.action = #selector(self.openAvailableRelease)
                self.versionButton.attributedTitle = NSAttributedString(
                    string: "Update Available \(version)",
                    attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                 .foregroundColor: NSColor.systemGreen,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue])
                self.versionButton.setAccessibilityLabel("MnM on Mac update \(version) available")
                self.showUpdatePrompt(version: version)
            }
        }.resume()
    }

    private func showUpdatePrompt(version: String) {
        guard !updatePromptShown, availableAssetURL != nil else { return }
        updatePromptShown = true
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update Available"
        alert.informativeText = "MnM on Mac \(version) is ready to install. The app will close briefly, replace the current version, and reopen automatically."
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { installAvailableUpdate() }
    }

    private func installAvailableUpdate() {
        guard let assetURL = availableAssetURL else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Downloading Update…"
        alert.informativeText = "Please keep MnM on Mac open while the update downloads."
        alert.addButton(withTitle: "Cancel")
        let task = URLSession.shared.downloadTask(with: assetURL) { [weak self] location, _, error in
            DispatchQueue.main.async {
                alert.window.orderOut(nil)
                guard let self, let location, error == nil else { return }
                self.finishInstallingUpdate(from: location)
            }
        }
        task.resume()
        alert.beginSheetModal(for: window)
    }

    private func finishInstallingUpdate(from archive: URL) {
        let appURL = Bundle.main.bundleURL
        let destination = appURL.deletingLastPathComponent()
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mnm-update-\(pid).sh")
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        #!/bin/sh
        archive=\(quote(archive.path))
        destination=\(quote(destination.path))
        app=\(quote(appURL.path))
        work=\"$TMPDIR/mnm-update-\(pid)\"
        mkdir -p \"$work\"
        ditto -x -k \"$archive\" \"$work\"
        newapp=\"$(find \"$work\" -maxdepth 2 -name '*.app' -type d | head -1)\"
        if [ -z \"$newapp\" ]; then exit 1; fi
        while kill -0 \(pid) 2>/dev/null; do sleep 1; done
        rm -rf \"$app\"
        ditto \"$newapp\" \"$app\"
        open \"$app\"
        rm -f \(quote(scriptURL.path))
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Update Failed"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    @objc private func openAvailableRelease() {
        if let availableReleaseURL { NSWorkspace.shared.open(availableReleaseURL) }
    }

    private func refresh() {
        guard !busy, window != nil else { return }
        setInitialSetupMode(false)
        if let failure = storageFailure {
            setReadyLayout(false)
            setErrorMessage(failure)
            playButton.isEnabled = false
            updateButton.isEnabled = false
            reauthenticateButton.isEnabled = false
            folderButton.isEnabled = false
            return
        }
        setupLogButton.isHidden = lastPatcherFailure == nil || !FileManager.default.fileExists(atPath: WinePaths.current.setupLog.path)
        folderButton.isEnabled = gameProcess?.isRunning != true && patcherProcess?.isRunning != true
        if let result = GameRunState.read(.current), result.updated > lastGameStatusUpdate {
            lastGameStatusUpdate = result.updated
            if result.state == "failed" { lastPatcherFailure = result.message }
            else { lastPatcherFailure = nil }
        }
        if gameProcess?.isRunning == true || GameRunState.isRunning(.current) {
            setErrorMessage(nil)
            setReadyLayout(true)
            graphicsBackendRow.alphaValue = 0.45
            statusLabel.stringValue = "Game is running"
            statusLabel.textColor = .systemGreen
            detailLabel.stringValue = "Enjoy Monsters & Memories."
            playButton.title = "Playing"
            playButton.isEnabled = false
            updateButton.isEnabled = false
            reauthenticateButton.isEnabled = false
            folderButton.isEnabled = false
            graphicsBackendButton.isEnabled = false
            hudButton.isEnabled = false
            return
        }
        if let patcher = patcherProcess, patcher.isRunning {
            setReadyLayout(false)
            let gameFound = WinePaths.current.selectedGame != nil
            let initialSetup = !UserDefaults.standard.bool(forKey: Self.completedInitialSetupKey)
            if closePatcherAfterInitialSetup && WineRuntime.readiness == "ready" && GameSession.hasRecordedInstallation {
                patcherReadyChecks += 1
                if patcherReadyChecks >= 2 {
                    expectedPatcherTermination = true
                    UserDefaults.standard.set(true, forKey: Self.completedInitialSetupKey)
                    statusLabel.stringValue = "Finishing setup"
                    statusLabel.textColor = .systemGreen
                    detailLabel.stringValue = "Closing the official launcher and preparing MnM on Mac."
                    playButton.isEnabled = false
                    patcher.terminate()
                    return
                }
            } else {
                patcherReadyChecks = 0
            }
            setInitialSetupMode(initialSetup)
            if initialSetup { updateSetupInfo(for: gameFound ? "needs_game" : "needs_login") }
            statusLabel.stringValue = gameFound ? "Finish in the official launcher" : "Official launcher is open"
            statusLabel.textColor = .labelColor
            detailLabel.stringValue = closePatcherAfterInitialSetup
                ? "Sign in and finish installing there. It will close automatically when setup is complete."
                : "Use it only to finish installing or updating. Close it when you are done."
            playButton.title = "Show Official Launcher"
            playButton.isEnabled = true
            if let failure = lastPatcherFailure {
                setErrorMessage(failure)
            } else {
                setErrorMessage(nil)
            }
            return
        }
        state = WineRuntime.readiness
        if state == "ready" { UserDefaults.standard.set(true, forKey: Self.completedInitialSetupKey) }
        let setupRequired = ["needs_wine", "needs_libraries", "needs_runtime_update", "needs_prefix", "missing_launcher"].contains(state)
        let initialSetup = !UserDefaults.standard.bool(forKey: Self.completedInitialSetupKey)
            && ["needs_login", "needs_game"].contains(state)
        let focusedSetup = setupRequired || initialSetup
        setInitialSetupMode(focusedSetup)
        setReadyLayout(state == "ready")
        playButton.title = LauncherStep(readiness: state)?.title ?? "Continue"
        playButton.isEnabled = true
        updateButton.isEnabled = true
        reauthenticateButton.isEnabled = true
        graphicsBackendButton.isEnabled = true
        hudButton.isEnabled = true
        updateButton.isHidden = false
        updateButton.title = "Install / Update / Login"
        statusLabel.textColor = .labelColor
        switch state {
        case "ready":
            statusLabel.stringValue = "Ready to play"
            statusLabel.textColor = .systemGreen
            detailLabel.stringValue = ""
        case "needs_login":
            let gameFound = WinePaths.current.selectedGame != nil
            statusLabel.stringValue = gameFound ? "Game installed — sign in to play" : "Sign in to play"
            detailLabel.stringValue = "Use the official launcher to sign in. When it shows Play, close it and return here."
            playButton.title = "Open Official Launcher"
        case "needs_game":
            statusLabel.stringValue = "Install Monsters & Memories"
            detailLabel.stringValue = "The official launcher downloads and verifies the game. Close it when it shows Play."
            playButton.title = "Install Game"
        case "needs_wine":
            statusLabel.stringValue = "Set up Wine to play"
            detailLabel.stringValue = "About 341 MB • usually takes 5–10 minutes."
        case "needs_libraries":
            statusLabel.stringValue = "Finish setting up Wine"
            detailLabel.stringValue = "About 81 MB • usually takes 2–5 minutes."
        case "needs_runtime_update":
            statusLabel.stringValue = "Runtime update available"
            detailLabel.stringValue = "About 83 MB • your prefixes, login, game files, and settings are preserved."
            playButton.title = "Update Runtime"
        case "needs_prefix":
            statusLabel.stringValue = "Finish setting up Wine"
            detailLabel.stringValue = "One local configuration step remains."
        case "needs_rosetta":
            statusLabel.stringValue = "Rosetta is required"
            detailLabel.stringValue = "Install Apple's Rosetta, then reopen this app."
            playButton.isEnabled = false
        case "missing_launcher":
            statusLabel.stringValue = "Install the official launcher"
            detailLabel.stringValue = "It is only used to sign in, install, and update the game."
            playButton.title = "Install Official Launcher"
        default:
            statusLabel.stringValue = "Unable to check the game"
            detailLabel.stringValue = "Reopen the app and try again."
            playButton.isEnabled = false
        }
        if let failure = lastPatcherFailure {
            statusLabel.stringValue = "Action needs attention"
            statusLabel.textColor = .systemOrange
            detailLabel.stringValue = failure
        }
        // Normal status descriptions are intentionally omitted from the hero.
        // Only actionable failures occupy the compact error section.
        setErrorMessage(storageFailure ?? lastPatcherFailure)
        if !busy && lastPatcherFailure == nil {
            switch state {
            case "needs_wine":
                setProgressMessage("Initial setup", detail: "First-time setup usually takes 5–10 minutes, depending on your connection.")
            case "needs_libraries":
                setProgressMessage("Initial setup", detail: "Installing support files usually takes a few minutes.")
            case "needs_prefix":
                setProgressMessage("Initial setup", detail: "One local setup step remains before you can play.")
            default:
                break
            }
        }
        if focusedSetup { updateSetupInfo(for: state) }
    }

    @objc private func play() {
        refresh()
        guard !busy, storageFailure == nil else { return }
        if patcherProcess?.isRunning == true { update(); return }
        switch LauncherStep(readiness: state) {
        case .setup: if state != "needs_rosetta" { setupWine() }; return
        case .update: update(); return
        default: break
        }
        guard state == "ready", gameProcess?.isRunning != true, patcherProcess?.isRunning != true else { return }
        if gameModeEnabled && !gameModeController.isAvailable {
            showGameModeRequirement()
            return
        }
        if ((selectedGraphicsBackend == .dxvk || selectedGraphicsBackend == .kosmicKrisp) && !WinePaths.current.dxvkInstalled) ||
           (selectedGraphicsBackend == .d3dMetal && !WinePaths.current.d3dMetalInstalled) {
            graphicsBackendChanged()
            return
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: NativePatcherInstaller.bundleID).allSatisfy({ $0.isTerminated }) else {
            showError("Quit the official patcher before playing here.")
            return
        }
        do {
            lastPatcherFailure = nil
            if gameModeEnabled && !gameModeController.activate() {
                throw PatcherSetupError.message("Game Mode could not be enabled. MnM checked the available macOS Game Mode tool, but activation was rejected. Turn Game Mode off in the cogwheel menu to continue.")
            }
            guard let bridge = Bundle.main.url(forResource: "MnMGameBridge", withExtension: nil) else {
                throw PatcherSetupError.message("The game launch helper is missing from this app.")
            }
            let process = Process()
            process.executableURL = bridge
            process.arguments = ["--from-app"]
            var environment = ProcessInfo.processInfo.environment
            environment["MNM_GRAPHICS_BACKEND"] = selectedGraphicsBackend.rawValue
            environment["MNM_GRAPHICS_HUD"] = performanceHUDEnabled ? "1" : "0"
            environment["MNM_METALFX_UPSCALING"] = metalFXUpscalingEnabled ? "1" : "0"
            environment["MNM_MSYNC"] = msyncEnabled ? "1" : "0"
            environment["MNM_TERMINAL_LOG"] = terminalLogEnabled ? "1" : "0"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] finished in
                DispatchQueue.main.async {
                    guard let self = self, self.gameProcess === finished else { return }
                    self.gameProcess = nil
                    self.gameModeController.deactivate()
                    if finished.terminationStatus != 0 {
                        self.lastPatcherFailure = "The game stopped (code \(finished.terminationStatus)). This Wine build is experimental."
                    }
                    self.refresh()
                }
            }
            gameProcess = process
            try process.run()
        } catch {
            gameProcess = nil
            gameModeController.deactivate()
            lastPatcherFailure = error.localizedDescription
        }
        refresh()
    }

    private func showGameModeRequirement() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Full Xcode Required for Game Mode"
        alert.informativeText = "Game Mode requires Apple’s full Xcode app. Would you like to download Xcode now?"
        alert.addButton(withTitle: "Yes, Download Xcode")
        alert.addButton(withTitle: "Turn Game Mode Off")
        if alert.runModal() == .alertFirstButtonReturn {
            let next = NSAlert()
            next.alertStyle = .warning
            next.messageText = "Restart MnM on Mac After Installing Xcode"
            next.informativeText = "Download Xcode from the App Store, open it once, and accept its license if prompted. Then quit and restart MnM on Mac so Game Mode can use it."
            next.addButton(withTitle: "Open Xcode in App Store")
            next.addButton(withTitle: "Close")
            if next.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "macappstore://itunes.apple.com/app/id497799835")!)
            }
        } else {
            UserDefaults.standard.set(false, forKey: Self.gameModeKey)
            updatePerformanceHUDButtonAppearance()
        }
    }

    @objc private func setupWine() {
        guard !busy, storageFailure == nil, patcherProcess?.isRunning != true, gameProcess?.isRunning != true, !GameRunState.isRunning(.current) else { return }
        let updatingRuntime = state == "needs_runtime_update"
        busy = true
        lastPatcherFailure = nil
        setInitialSetupMode(true)
        playButton.isEnabled = false
        startSetupAnimation()
        updateButton.isEnabled = false
        reauthenticateButton.isEnabled = false
        folderButton.isEnabled = false
        setupLogButton.isHidden = true
        let setupEstimate = updatingRuntime
            ? "Updating support files. Your existing Windows environments and game data will not be changed."
            : "First-time setup usually takes 5–10 minutes, depending on your connection."
        setProgressMessage(updatingRuntime ? "Updating runtime…" : "Setting up Wine…", detail: setupEstimate)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try WineInstaller(paths: .current).install { message in
                    DispatchQueue.main.async {
                        self.setProgressMessage(message, detail: setupEstimate)
                    }
                }
                DispatchQueue.main.async {
                    self.stopSetupAnimation()
                    self.busy = false
                    self.folderButton.isEnabled = true
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.stopSetupAnimation()
                    self.busy = false
                    self.folderButton.isEnabled = true
                    self.lastPatcherFailure = error.localizedDescription
                    self.refresh()
                }
            }
        }
    }

    private func startSetupAnimation() {
        setupAnimationTimer?.invalidate()
        setupAnimationFrame = 1
        updateSetupAnimationTitle()
        setupAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.setupAnimationFrame = self.setupAnimationFrame % 3 + 1
            self.updateSetupAnimationTitle()
        }
    }

    private func updateSetupAnimationTitle() {
        let title = NSMutableAttributedString(string: "Setting Up...")
        if setupAnimationFrame < 3 {
            title.addAttribute(hiddenSetupDotAttribute, value: true,
                               range: NSRange(location: 10 + setupAnimationFrame, length: 3 - setupAnimationFrame))
        }
        playButton.attributedTitle = title
    }

    private func stopSetupAnimation() {
        setupAnimationTimer?.invalidate()
        setupAnimationTimer = nil
    }

    private func setInitialSetupMode(_ active: Bool) {
        // Setup explanations are intentionally not shown in the hero card.
        launcherSectionLabel.isHidden = true
        setupInfo.isHidden = true
        fileActions.isHidden = active
        if active { setReadyLayout(false) }
        sectionDivider.isHidden = active
        officialSectionLabel.isHidden = false
        accountActions.isHidden = false
        maintenanceCard.isHidden = false
    }

    private func setReadyLayout(_ active: Bool) {
        graphicsBackendRow.isHidden = !active
        graphicsBackendRow.alphaValue = 1
    }

    private func setErrorMessage(_ message: String?) {
        guard let message, !message.isEmpty else {
            statusLabel.isHidden = true
            detailLabel.isHidden = true
            errorGroup.isHidden = true
            errorGroupHeightConstraint.constant = 0
            heroHeightConstraint.constant = fileActions.isHidden ? 150 : 212
            return
        }
        let combined = "Action needs attention — \(message)"
        statusLabel.stringValue = combined
        statusLabel.font = fittingErrorFont(for: combined, width: 300)
        statusLabel.textColor = .systemOrange
        detailLabel.stringValue = ""
        statusLabel.maximumNumberOfLines = 1
        statusLabel.cell?.usesSingleLineMode = true
        statusLabel.cell?.wraps = false
        errorGroupHeightConstraint.constant = 24
        statusLabel.isHidden = false
        detailLabel.isHidden = true
        errorGroup.isHidden = false
        heroHeightConstraint.constant = 212
    }

    private func fittingErrorFont(for text: String, width: CGFloat) -> NSFont {
        for size in stride(from: 12.0, through: 7.0, by: -0.5) {
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            if (text as NSString).size(withAttributes: [.font: font]).width <= width { return font }
        }
        return NSFont.systemFont(ofSize: 7, weight: .semibold)
    }

    private func setProgressMessage(_ title: String, detail: String = "") {
        statusLabel.stringValue = title
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .labelColor
        detailLabel.stringValue = detail
        errorGroupHeightConstraint.constant = detail.isEmpty ? 30 : 58
        statusLabel.isHidden = false
        detailLabel.isHidden = detail.isEmpty
        errorGroup.isHidden = false
        heroHeightConstraint.constant = 200
    }

    private var selectedGraphicsBackend: GraphicsBackend {
        guard let value = UserDefaults.standard.string(forKey: Self.graphicsBackendKey),
              let backend = GraphicsBackend(rawValue: value),
              backend != .kosmicKrisp else { return .d3dMetal }
        return backend
    }

    private var performanceHUDKey: String {
        switch selectedGraphicsBackend {
        case .metal: return Self.metalPerformanceHUDKey
        case .dxvk: return Self.dxvkPerformanceHUDKey
        case .kosmicKrisp: return Self.kosmicKrispPerformanceHUDKey
        case .d3dMetal: return Self.d3dMetalPerformanceHUDKey
        }
    }

    private var performanceHUDEnabled: Bool {
        UserDefaults.standard.bool(forKey: performanceHUDKey)
    }

    private var metalFXUpscalingEnabled: Bool {
        selectedGraphicsBackend == .metal && UserDefaults.standard.bool(forKey: Self.metalFXUpscalingKey)
    }

    private var gameModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.gameModeKey)
    }

    private var msyncEnabled: Bool {
        guard UserDefaults.standard.object(forKey: Self.msyncEnabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: Self.msyncEnabledKey)
    }

    private var terminalLogEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.terminalLogKey)
    }

    private func updatePerformanceHUDButtonAppearance() {
        guard hudButton != nil else { return }
        let hudEnabled = performanceHUDEnabled
        let gameMode = gameModeEnabled
        let metalFXEnabled = metalFXUpscalingEnabled
        let statusItems = [
            "Performance HUD: \(hudEnabled ? "On" : "Off")",
            "Game Mode: \(gameMode ? "On" : "Off")"
        ] + (selectedGraphicsBackend == .metal ? ["MetalFX Upscaling: \(metalFXEnabled ? "On" : "Off")"] : [])
        hudButton.toolTip = statusItems.joined(separator: " • ")
        hudButton.contentTintColor = (hudEnabled || gameMode || metalFXEnabled) ? .systemGreen : .secondaryLabelColor
        hudButton.setAccessibilityLabel("Graphics, performance, and Game Mode settings")
        hudButton.setAccessibilityValue(statusItems.joined(separator: ", "))
    }

    @objc private func showPerformanceHUDMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let renderer: String
        switch selectedGraphicsBackend {
        case .metal: renderer = "DXMT"
        case .dxvk: renderer = "DXVK"
        case .kosmicKrisp: renderer = "KosmicKrisp"
        case .d3dMetal: renderer = "D3DMetal"
        }
        let msyncItem = NSMenuItem(title: "MSync (Recommended)", action: #selector(toggleMSync), keyEquivalent: "")
        msyncItem.target = self
        msyncItem.state = msyncEnabled ? .on : .off
        menu.addItem(msyncItem)
        menu.addItem(.separator())
        let gameModeItem = NSMenuItem(title: "Game Mode", action: #selector(toggleGameMode), keyEquivalent: "")
        gameModeItem.target = self
        gameModeItem.state = gameModeEnabled ? .on : .off
        gameModeItem.isEnabled = gameModeController.isAvailable
        menu.addItem(gameModeItem)
        menu.addItem(.separator())
        if selectedGraphicsBackend == .metal {
            let metalFXItem = NSMenuItem(title: "MetalFX Upscaling", action: #selector(toggleMetalFXUpscaling), keyEquivalent: "")
            metalFXItem.target = self
            metalFXItem.state = metalFXUpscalingEnabled ? .on : .off
            metalFXItem.toolTip = "Uses a true 1280 × 720 DXMT render surface, then MetalFX upscales it to 1920 × 1080 on the next launch."
            menu.addItem(metalFXItem)
            menu.addItem(.separator())
        }
        let item = NSMenuItem(title: "\(renderer) Performance HUD", action: #selector(togglePerformanceHUD), keyEquivalent: "")
        item.target = self
        item.state = performanceHUDEnabled ? .on : .off
        menu.addItem(item)
        menu.addItem(.separator())
        let terminalLogItem = NSMenuItem(title: "Terminal Log", action: #selector(toggleTerminalLog), keyEquivalent: "")
        terminalLogItem.target = self
        terminalLogItem.state = terminalLogEnabled ? .on : .off
        terminalLogItem.toolTip = "This will open a Terminal window to show live Wine output on the next game launch."
        menu.addItem(terminalLogItem)
        menu.addItem(.separator())
        let noteTitle = gameModeController.isAvailable
            ? "Applies on next game launch"
            : "Game Mode requires Xcode Command Line Tools"
        let note = NSMenuItem(title: noteTitle, action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        menu.popUp(positioning: item, at: NSPoint(x: sender.bounds.midX, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func togglePerformanceHUD() {
        let defaults = UserDefaults.standard
        defaults.set(!performanceHUDEnabled, forKey: performanceHUDKey)
        updatePerformanceHUDButtonAppearance()
    }

    @objc private func toggleMetalFXUpscaling() {
        guard selectedGraphicsBackend == .metal else { return }
        let defaults = UserDefaults.standard
        defaults.set(!metalFXUpscalingEnabled, forKey: Self.metalFXUpscalingKey)
        updatePerformanceHUDButtonAppearance()
    }

    @objc private func toggleGameMode() {
        UserDefaults.standard.set(!gameModeEnabled, forKey: Self.gameModeKey)
        updatePerformanceHUDButtonAppearance()
    }

    @objc private func toggleMSync() {
        UserDefaults.standard.set(!msyncEnabled, forKey: Self.msyncEnabledKey)
        updatePerformanceHUDButtonAppearance()
    }

    @objc private func toggleTerminalLog() {
        if !terminalLogEnabled {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Enable Terminal Log?"
            alert.informativeText = "Terminal Log is intended for debugging Wine. It opens a live Terminal window and may noticeably reduce game performance while enabled."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        UserDefaults.standard.set(!terminalLogEnabled, forKey: Self.terminalLogKey)
        updatePerformanceHUDButtonAppearance()
    }

    @objc private func graphicsBackendChanged() {
        let backend: GraphicsBackend
        switch graphicsBackendButton.indexOfSelectedItem {
        case 0: backend = .d3dMetal
        case 1: backend = .metal
        case 2: backend = .dxvk
        case 3: backend = .kosmicKrisp
        default: backend = .d3dMetal
        }
        guard backend != .metal else {
            UserDefaults.standard.set(GraphicsBackend.metal.rawValue, forKey: Self.graphicsBackendKey)
            updatePerformanceHUDButtonAppearance()
            return
        }

        let confirmationKey: String
        switch backend {
        case .dxvk: confirmationKey = Self.confirmedDXVKKey
        case .kosmicKrisp: confirmationKey = Self.confirmedKosmicKrispKey
        case .d3dMetal: confirmationKey = Self.confirmedD3DMetalKey
        case .metal: return
        }
        if !UserDefaults.standard.bool(forKey: confirmationKey) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            if backend == .dxvk {
                alert.messageText = "Use Experimental DXVK?"
                alert.informativeText = "DXVK is an optional third-party graphics backend being tested with Monsters & Memories. It uses a separate copy of the Windows environment, so the normal setup stays untouched. Its maintainer warns that replacing Direct3D libraries in an online game may be unsupported or treated as cheating. D3DMetal remains the recommended option."
                alert.addButton(withTitle: "Install & Use DXVK")
            } else if backend == .kosmicKrisp {
                alert.messageText = "Use Experimental KosmicKrisp?"
                alert.informativeText = "KosmicKrisp runs DXVK through a new Vulkan-on-Metal driver included with Sikarugir 1.0.15. It uses a separate Windows environment and may have compatibility, performance, or visual issues. D3DMetal remains the recommended option."
                alert.addButton(withTitle: "Install & Use KosmicKrisp")
            } else {
                alert.messageText = "Use D3DMetal?"
                alert.informativeText = "D3DMetal 3.0 is Apple’s Game Porting Toolkit graphics layer. It is licensed for non-commercial development, testing, and evaluation on Apple hardware. MnM on Mac will download it from the Sikarugir 1.0.15 support package and use a separate Windows environment. Review Apple’s license in About before continuing."
                alert.addButton(withTitle: "I Agree & Install")
            }
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                graphicsBackendButton.selectItem(at: 1)
                UserDefaults.standard.set(GraphicsBackend.metal.rawValue, forKey: Self.graphicsBackendKey)
                updatePerformanceHUDButtonAppearance()
                return
            }
            UserDefaults.standard.set(true, forKey: confirmationKey)
        }

        let alreadyInstalled: Bool
        switch backend {
        case .dxvk, .kosmicKrisp: alreadyInstalled = WinePaths.current.dxvkInstalled
        case .d3dMetal: alreadyInstalled = WinePaths.current.d3dMetalInstalled
        case .metal: alreadyInstalled = true
        }
        if alreadyInstalled {
            UserDefaults.standard.set(backend.rawValue, forKey: Self.graphicsBackendKey)
            updatePerformanceHUDButtonAppearance()
            return
        }

        busy = true
        playButton.isEnabled = false
        updateButton.isEnabled = false
        reauthenticateButton.isEnabled = false
        folderButton.isEnabled = false
        graphicsBackendButton.isEnabled = false
        let displayName: String
        switch backend {
        case .dxvk: displayName = "DXVK"
        case .kosmicKrisp: displayName = "KosmicKrisp"
        case .d3dMetal: displayName = "D3DMetal"
        case .metal: displayName = "DXMT"
        }
        setProgressMessage("Installing \(displayName)…")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report: (String) -> Void = { message in
                    DispatchQueue.main.async { self.statusLabel.stringValue = message }
                }
                if backend == .dxvk || backend == .kosmicKrisp {
                    try DXVKInstaller(paths: .current).install(progress: report)
                } else {
                    try D3DMetalInstaller(paths: .current).install(progress: report)
                }
                DispatchQueue.main.async {
                    UserDefaults.standard.set(backend.rawValue, forKey: Self.graphicsBackendKey)
                    self.updatePerformanceHUDButtonAppearance()
                    self.busy = false
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    UserDefaults.standard.set(GraphicsBackend.metal.rawValue, forKey: Self.graphicsBackendKey)
                    self.graphicsBackendButton.selectItem(at: 1)
                    self.updatePerformanceHUDButtonAppearance()
                    self.lastPatcherFailure = error.localizedDescription
                    self.busy = false
                    self.refresh()
                }
            }
        }
    }

    private func updateSetupInfo(for setupState: String) {
        switch setupState {
        case "needs_wine":
            setupInfoTitle.stringValue = "Why Wine is needed"
            setupInfoBody.stringValue = "Monsters & Memories is built for Windows. Wine lets it run on your Mac inside a private environment, with no separate CrossOver installation required."
        case "needs_libraries":
            setupInfoTitle.stringValue = "Why support files are needed"
            setupInfoBody.stringValue = "These files supply the Windows libraries and graphics translation required by the official launcher and game."
        case "needs_runtime_update":
            setupInfoTitle.stringValue = "What this update changes"
            setupInfoBody.stringValue = "Only the shared Sikarugir support libraries are updated. Your Wine engine, prefixes, login, game files, and settings stay in place."
        case "needs_prefix":
            setupInfoTitle.stringValue = "Why a Windows environment is needed"
            setupInfoBody.stringValue = "This Windows environment keeps Wine, the official launcher, game files, and settings together without changing the rest of your Mac."
        case "missing_launcher", "needs_login":
            setupInfoTitle.stringValue = "Why the official launcher is needed"
            setupInfoBody.stringValue = "It handles signing in, installing, and updating. Once setup finishes, it closes automatically and MnM on Mac becomes your normal Play button."
        case "needs_game":
            setupInfoTitle.stringValue = "What the official launcher is doing"
            setupInfoBody.stringValue = "It downloads and verifies Monsters & Memories. When the game is ready, the launcher closes automatically to finish setup."
        default:
            setupInfoTitle.stringValue = "What setup is doing"
            setupInfoBody.stringValue = "MnM on Mac is preparing the components required to run the game."
        }
    }

    private func updateSetupInfo(forProgress message: String) {
        if message.localizedCaseInsensitiveContains("DXMT") || message.localizedCaseInsensitiveContains("graphics") {
            setupInfoTitle.stringValue = "Why graphics support is needed"
            setupInfoBody.stringValue = "It translates the game’s DirectX graphics for macOS and Apple silicon."
        } else if message.localizedCaseInsensitiveContains("support libraries") {
            setupInfoTitle.stringValue = "Why support files are needed"
            setupInfoBody.stringValue = "They provide the Windows components the official launcher and game expect."
        } else if message.localizedCaseInsensitiveContains("Windows environment") {
            setupInfoTitle.stringValue = "Why a Windows environment is needed"
            setupInfoBody.stringValue = "It keeps the launcher, game, and Wine settings together without requiring CrossOver."
        } else {
            setupInfoTitle.stringValue = "Why Wine is needed"
            setupInfoBody.stringValue = "Wine is the compatibility layer that lets the Windows game run on your Mac."
        }
    }

    @objc private func update() {
        guard !busy, storageFailure == nil, gameProcess?.isRunning != true, !GameRunState.isRunning(.current) else { return }
        if let patcher = patcherProcess, patcher.isRunning {
            NSRunningApplication(processIdentifier: patcher.processIdentifier)?.activate(options: [])
            return
        }
        let otherPatchers = NSRunningApplication.runningApplications(withBundleIdentifier: "com.monstersandmemories.mnm-patcher-app")
            .filter { !$0.isTerminated }
        if !otherPatchers.isEmpty {
            setErrorMessage("Close the other MnM patcher, then try again.")
            otherPatchers.first?.activate(options: [])
            return
        }
        guard resolveStaleLauncherStateIfNeeded() else { return }

        busy = true
        updateButton.isEnabled = false
        reauthenticateButton.isEnabled = false
        playButton.isEnabled = false
        lastPatcherFailure = nil
        defer { busy = false; refresh() }

        let nativePath = runHelper(["native-path"])
        if nativePath.code != 0 {
            downloadPatcher()
            return
        }
        let workingPath = runHelper(["patch-directory"])
        guard nativePath.code == 0, workingPath.code == 0 else {
            lastPatcherFailure = nativePath.code != 0 ? nativePath.text : workingPath.text
            return
        }
        let plan = PatcherLaunchPlan(
            executableURL: URL(fileURLWithPath: nativePath.text).appendingPathComponent("Contents/MacOS/" + PatcherBundleGuard.executableName),
            workingDirectoryURL: URL(fileURLWithPath: workingPath.text, isDirectory: true),
            environmentOverrides: [
                "MNM_GRAPHICS_BACKEND": selectedGraphicsBackend.rawValue,
                "MNM_GRAPHICS_HUD": performanceHUDEnabled ? "1" : "0"
            ])
        do {
            guard let guardExecutable = Bundle.main.url(forResource: PatcherBundleGuard.executableName, withExtension: nil),
                  let bridgeExecutable = Bundle.main.url(forResource: "MnMGameBridge", withExtension: nil),
                  let redirectLibrary = Bundle.main.url(forResource: "MnMPlayRedirect", withExtension: "dylib") else {
                throw PatcherSetupError.message("The patcher startup helper is missing from this app.")
            }
            try PatcherBundleGuard.prepare(app: URL(fileURLWithPath: nativePath.text), guardExecutable: guardExecutable,
                                           bridgeExecutable: bridgeExecutable, redirectLibrary: redirectLibrary)
            try FileManager.default.createDirectory(at: plan.workingDirectoryURL, withIntermediateDirectories: true)
            let process = plan.makeProcess()
            process.terminationHandler = { [weak self] finished in
                DispatchQueue.main.async {
                    guard let self = self, self.patcherProcess === finished else { return }
                    let expectedTermination = self.expectedPatcherTermination
                    self.patcherProcess = nil
                    self.closePatcherAfterInitialSetup = false
                    self.patcherReadyChecks = 0
                    self.expectedPatcherTermination = false
                    if !expectedTermination && finished.terminationStatus != 0 {
                        self.lastPatcherFailure = "The official launcher stopped (code \(finished.terminationStatus)). Reopen it and try again."
                    }
                    self.refresh()
                }
            }
            closePatcherAfterInitialSetup = !UserDefaults.standard.bool(forKey: Self.completedInitialSetupKey)
                && WineRuntime.readiness != "ready"
            patcherReadyChecks = 0
            expectedPatcherTermination = false
            patcherProcess = process
            try process.run()
        } catch {
            patcherProcess = nil
            closePatcherAfterInitialSetup = false
            patcherReadyChecks = 0
            expectedPatcherTermination = false
            lastPatcherFailure = "The MnM patcher could not open: \(error.localizedDescription)"
        }
    }

    private func downloadPatcher() {
        DispatchQueue.main.async {
            self.busy = true
            self.playButton.isEnabled = false
            self.playButton.title = "Downloading…"
            self.updateButton.isEnabled = false
            self.statusLabel.stringValue = "Downloading MnM patcher…"
            self.detailLabel.stringValue = "This only needs to be set up once."
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let installer = NativePatcherInstaller(toolsDirectory: NativePatcherInstaller.defaultToolsDirectory)
                    _ = try installer.install { message in
                        DispatchQueue.main.async {
                            self.statusLabel.stringValue = message
                            self.detailLabel.stringValue = "Used only to sign in, install, and update. Close it when it shows Play."
                            self.setupInfoTitle.stringValue = "Why the official launcher is needed"
                            self.setupInfoBody.stringValue = "It handles signing in, installing, and updating. When it shows Play, close it and return here—MnM on Mac becomes your normal Play button."
                        }
                    }
                    guard runHelper(["native-path"]).code == 0 else {
                        throw PatcherSetupError.message("The installed patcher could not be found. Reopen MnM on Mac and try again.")
                    }
                    DispatchQueue.main.async {
                        self.busy = false
                        self.refresh()
                        self.update()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.busy = false
                        self.lastPatcherFailure = "Setup could not finish: \(error.localizedDescription)"
                        self.refresh()
                    }
                }
            }
        }
    }

    @objc private func chooseFolder() {
        guard !busy, storageFailure == nil, gameProcess?.isRunning != true, patcherProcess?.isRunning != true, !GameRunState.isRunning(.current) else { return }
        let picker = NSOpenPanel()
        picker.title = "Choose your Monsters & Memories game folder"
        picker.message = "Select the folder that directly contains mnm.exe."
        picker.prompt = "Use Game Folder"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        let result = runHelper(["remember-game", folder.path])
        if result.code != 0 { showError(result.text) }
        refresh()
    }

    private func resolveStaleLauncherStateIfNeeded() -> Bool {
        guard WinePaths.current.selectedGame == nil, GameSession.hasRecordedInstallation else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Existing Launcher Data Found"
        alert.informativeText = "The official launcher remembers an installed game, but MnM on Mac cannot find those game files. Reset the old launcher state to install a fresh copy, or choose the existing folder containing mnm.exe."
        alert.addButton(withTitle: "Reset and Reinstall")
        alert.addButton(withTitle: "Choose Existing Game Folder…")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                _ = try AppStorage.backupOfficialLauncherData()
                return true
            } catch {
                showError("The old launcher data could not be backed up: \(error.localizedDescription)")
                return false
            }
        case .alertSecondButtonReturn:
            chooseFolder()
            return false
        default:
            return false
        }
    }

    @objc private func reauthenticate() {
        guard !busy, patcherProcess?.isRunning != true, gameProcess?.isRunning != true else { return }
        let otherPatchers = NSRunningApplication.runningApplications(withBundleIdentifier: NativePatcherInstaller.bundleID)
            .contains { !$0.isTerminated }
        guard !otherPatchers else {
            showError("Close the official MnM launcher before re-authenticating.")
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Re-authenticate with Monsters & Memories?"
        let warning = NSTextField(wrappingLabelWithString: "This will reset your saved login session. You will need to sign in again through the official Monsters & Memories launcher. Your installed game files will not be deleted, and the old launcher data will be backed up.")
        warning.textColor = .systemRed
        warning.font = .systemFont(ofSize: 12, weight: .medium)
        warning.preferredMaxLayoutWidth = 380
        warning.frame = NSRect(x: 0, y: 0, width: 380, height: 58)
        alert.accessoryView = warning
        alert.addButton(withTitle: "Re-authenticate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try AppStorage.backupOfficialLauncherData()
            lastPatcherFailure = nil
            refresh()
            update()
        } catch {
            showError("The old login data could not be backed up: \(error.localizedDescription)")
        }
    }

    @objc private func openInstallDirectory() {
        if let failure = storageFailure { showError(failure); return }
        let result = runHelper(["install-directory"])
        guard result.code == 0, !result.text.isEmpty else {
            showError("The app's data folder could not be located.")
            return
        }
        let directory = URL(fileURLWithPath: result.text, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(directory) {
                showError("Finder could not open the app's data folder.")
            }
        } catch {
            showError("The app's data folder could not be opened: \(error.localizedDescription)")
        }
    }

    @objc private func openSetupLog() {
        let log = WinePaths.current.setupLog
        guard FileManager.default.fileExists(atPath: log.path) else {
            showError("No setup log yet. Try Set Up Wine first.")
            return
        }
        if !NSWorkspace.shared.open(log) { showError("The setup log could not be opened.") }
    }

    @objc private func showThirdPartySoftware() {
        if thirdPartyWindow == nil { thirdPartyWindow = makeThirdPartyWindow() }
        thirdPartyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showLegalExplanation() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Legal & Compatibility"
        alert.informativeText = "MnM on Mac is a native Swift app that makes the existing Mac and Wine setup much easier while staying within the Master User Agreement. It creates a self-contained Wine environment, but still relies entirely on the official Monsters & Memories launcher for logging in, installing, updating, and repairing the game. All account and download communication stays between the official launcher and NWC’s servers.\n\nThe only thing MnM on Mac changes is the local Play handoff, which can loop or fail on macOS. We redirect that handoff into the correct Wine environment so the game launches properly. After setup, players can use MnM on Mac’s Play button for convenience and open the official launcher whenever they need to log in, update, or repair. We don’t recreate or reverse-engineer any NWC services.\n\nMonsters & Memories, its name, logos, artwork, official launcher, game assets, and all related materials belong solely to Niche Worlds Cult and its licensors. MnM on Mac claims no ownership of those materials and is an independent community compatibility tool that is not affiliated with or endorsed by Niche Worlds Cult."
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "View Master User Agreement")
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(Self.masterUserAgreementURL)
            }
        }
    }

    private func makeThirdPartyWindow() -> NSWindow {
        let acknowledgements = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let heading: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let secondary: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        func text(_ value: String, attributes: [NSAttributedString.Key: Any] = body) {
            acknowledgements.append(NSAttributedString(string: value, attributes: attributes))
        }
        func link(_ title: String, _ address: String) {
            guard let url = URL(string: address) else { return }
            acknowledgements.append(NSAttributedString(
                string: title,
                attributes: [.font: NSFont.systemFont(ofSize: 12), .link: url]))
        }
        func credit(_ name: String, detail: String, sourceTitle: String, source: String,
                    licenseTitle: String, license: String) {
            text(name + "\n", attributes: heading)
            text(detail + "\n", attributes: secondary)
            link(sourceTitle, source)
            text("  •  ", attributes: secondary)
            link(licenseTitle, license)
            text("\n\n")
        }

        text("About MnM on Mac\n", attributes: heading)
        text("Created by Matthew Centonze. Built to give Mac players a clean, approachable way to install, update, and launch Monsters & Memories through Wine.\n", attributes: secondary)
        link("Matthew Centonze on GitHub", "https://github.com/seathasky")
        text("\n\nMonsters & Memories\n", attributes: heading)
        text("The game is created by the official Monsters & Memories development team. Full credit and thanks go to them for bringing its world to life.\n", attributes: secondary)
        link("Official Monsters & Memories Website", "https://monstersandmemories.com/")
        text("\n\n")
        text("Third-Party Software\n", attributes: heading)
        text("This app is made possible by independent open-source projects and the people who maintain them. Thank you to every contributor.\n\n")
        credit("Wine", detail: "WineHQ contributors — the Windows compatibility layer.",
               sourceTitle: "Source", source: "https://gitlab.winehq.org/wine/wine",
               licenseTitle: "LGPL 2.1 License", license: "https://gitlab.winehq.org/wine/wine/-/blob/master/COPYING.LIB")
        credit("Sikarugir Wine Engine", detail: "Gcenx and the Sikarugir contributors — macOS Wine engine builds and support.",
               sourceTitle: "Engine Releases", source: "https://github.com/Sikarugir-App/Engines/releases",
               licenseTitle: "Project & Licensing", license: "https://github.com/Sikarugir-App/Sikarugir")
        credit("DXMT 0.80", detail: "Feifan He (3Shain) and DXMT contributors — Direct3D 10/11 translation for Metal.",
               sourceTitle: "Source", source: "https://github.com/3Shain/dxmt/tree/v0.80",
               licenseTitle: "MIT License", license: "https://github.com/3Shain/dxmt/blob/v0.80/LICENSE")
        credit("DXVK 1.10.3 for macOS", detail: "Gcenx, Philip Rebohle, and DXVK contributors — the experimental Vulkan-based graphics option.",
               sourceTitle: "macOS Release", source: "https://github.com/Gcenx/DXVK-macOS/releases/tag/v1.10.3",
               licenseTitle: "zlib License", license: "https://github.com/doitsujin/dxvk/blob/v1.10.3/LICENSE")
        credit("KosmicKrisp", detail: "Mesa and KosmicKrisp contributors — the experimental Vulkan-on-Metal driver supplied by Sikarugir.",
               sourceTitle: "Source", source: "https://github.com/Kenji-NX/mesa/tree/main/src/kosmickrisp",
               licenseTitle: "MIT License", license: "https://github.com/Kenji-NX/mesa/blob/main/docs/license.rst")
        credit("D3DMetal 3.0", detail: "Apple — the Game Porting Toolkit graphics layer, supplied through the Sikarugir 1.0.15 support package for testing.",
               sourceTitle: "Sikarugir Package", source: "https://github.com/Sikarugir-App/Wrapper/releases/tag/v1.0",
               licenseTitle: "Apple GPTK", license: "https://developer.apple.com/games/game-porting-toolkit/")
        credit("MacGamingFix", detail: "evertjr — reference implementation for the optional macOS Game Mode control.",
               sourceTitle: "Source", source: "https://github.com/evertjr/MacGamingFix",
               licenseTitle: "MIT License", license: "https://github.com/evertjr/MacGamingFix/blob/main/LICENSE")
        credit("wine-msync", detail: "Marzent and contributors — Mach semaphore synchronization for Wine on macOS.",
               sourceTitle: "Source", source: "https://github.com/marzent/wine-msync",
               licenseTitle: "LGPL 2.1 License", license: "https://github.com/marzent/wine-msync/blob/main/LICENSE")
        text("MnM on Mac is an independent community project. Third-party names belong to their respective owners.", attributes: secondary)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.linkTextAttributes = [
            .foregroundColor: Self.accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.textStorage?.setAttributedString(acknowledgements)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let credits = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        credits.title = "About MnM on Mac"
        credits.isReleasedWhenClosed = false
        credits.contentView?.addSubview(scrollView)
        if let contentView = credits.contentView {
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
                scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
                scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
                scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
            ])
        }
        credits.center()
        return credits
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "MnM on Mac"
        alert.informativeText = message
        alert.runModal()
    }

    func applicationDidBecomeActive(_ notification: Notification) { refresh() }
    func applicationWillTerminate(_ notification: Notification) { gameModeController.deactivate() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        refresh()
        return true
    }
}
