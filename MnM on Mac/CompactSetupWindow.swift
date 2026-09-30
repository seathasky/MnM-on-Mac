import AppKit

/// Visible only while support files/the official launcher are being prepared.
final class CompactSetupWindow {
    let window: NSWindow
    private let status = NSTextField(wrappingLabelWithString: "Preparing the official launcher…")
    private let detail = NSTextField(wrappingLabelWithString: "Setting up Wine and graphics support. The official Monsters & Memories launcher will open when setup is complete.")
    private let estimate = NSTextField(wrappingLabelWithString: "First-time setup can take 5–15 minutes, depending on your Mac and internet speed.")
    private let spinner = NSProgressIndicator()
    private let retry: NSButton

    init(target: AnyObject, retryAction: Selector) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MnM on Mac — Setup"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "MnM on Mac")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Preparing Monsters & Memories for your Mac")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.maximumNumberOfLines = 2
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 3
        estimate.font = .systemFont(ofSize: 16, weight: .bold)
        estimate.textColor = .labelColor
        estimate.maximumNumberOfLines = 3
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let progress = NSStackView(views: [spinner, status])
        progress.spacing = 10
        progress.alignment = .centerY
        retry = NSButton(title: "Try Again", target: target, action: retryAction)
        retry.isHidden = true
        let stack = NSStackView(views: [title, subtitle, progress, detail, estimate, retry])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            status.widthAnchor.constraint(equalToConstant: 392),
            detail.widthAnchor.constraint(equalToConstant: 432),
            estimate.widthAnchor.constraint(equalToConstant: 432)
        ])
        window.center()
    }

    func show() { window.makeKeyAndOrderFront(nil) }
    func render(message: String, explanation: String, failed: Bool) {
        status.stringValue = message
        detail.stringValue = explanation
        status.textColor = failed ? .systemOrange : .labelColor
        retry.isHidden = !failed
        if failed { spinner.stopAnimation(nil) } else { spinner.startAnimation(nil) }
    }
}
