import AppKit

struct AboutWindowContent {
    let appName: String
    let versionText: String
    let headline: String
    let subheadline: String
    let copyrightText: String
    let developerLabel: String
    let developerName: String
    let affiliationLines: [String]
    let footerText: String

    static func current(bundle: Bundle = .main) -> AboutWindowContent {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return AboutWindowContent(
            appName: NanumCsvViewerMacApp.displayName,
            versionText: "버전 \(shortVersion)(\(build))",
            headline: "Nanum CSV Viewer for macOS",
            subheadline: "Large CSV file viewer and analysis tool for macOS",
            copyrightText: "Copyright © 2026 Min-Gul Kim. All rights reserved.",
            developerLabel: "Developed by",
            developerName: "Min-Gul Kim, MD, PhD",
            affiliationLines: [
                "Professor",
                "Department of Pharmacology",
                "Jeonbuk National University Medical School",
                "CEO",
                "Nanum Space Co., Ltd."
            ],
            footerText: "© 2026 김민걸"
        )
    }
}

enum AboutTypography {
    static let appNameSize: CGFloat = 18
    static let versionSize: CGFloat = 12
    static let headlineSize: CGFloat = 15
    static let subheadlineSize: CGFloat = 13
    static let bodySize: CGFloat = 13
    static let footerSize: CGFloat = 12
}

@MainActor
final class AboutWindowController: NSWindowController {
    private let content: AboutWindowContent

    init(content: AboutWindowContent = .current()) {
        self.content = content
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = content.appName
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.contentView = AboutContentView(content: content)
        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

@MainActor
private final class AboutContentView: NSView {
    init(content: AboutWindowContent) {
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 540))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildLayout(content: content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildLayout(content: AboutWindowContent) {
        let topPanel = NSView()
        topPanel.translatesAutoresizingMaskIntoConstraints = false
        topPanel.wantsLayer = true
        topPanel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let bottomPanel = NSView()
        bottomPanel.translatesAutoresizingMaskIntoConstraints = false
        bottomPanel.wantsLayer = true
        bottomPanel.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let mainStack = NSStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 8

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let appName = label(content.appName, size: AboutTypography.appNameSize, weight: .bold)
        let version = label(content.versionText, size: AboutTypography.versionSize, weight: .semibold, color: .secondaryLabelColor)
        let headline = label(content.headline, size: AboutTypography.headlineSize, weight: .bold)
        let subheadline = label(content.subheadline, size: AboutTypography.subheadlineSize, weight: .regular, color: .secondaryLabelColor)
        let copyright = label(content.copyrightText, size: AboutTypography.bodySize, weight: .bold)
        let developerLabel = label(content.developerLabel, size: AboutTypography.bodySize, weight: .semibold)
        let developerName = label(content.developerName, size: AboutTypography.bodySize, weight: .bold)

        let affiliations = NSStackView()
        affiliations.translatesAutoresizingMaskIntoConstraints = false
        affiliations.orientation = .vertical
        affiliations.alignment = .centerX
        affiliations.spacing = 2
        for (index, line) in content.affiliationLines.enumerated() {
            if index == 3 {
                affiliations.addArrangedSubview(spacer(height: 8))
            }
            let weight: NSFont.Weight = (index == 0 || index == 3) ? .bold : .semibold
            affiliations.addArrangedSubview(label(line, size: AboutTypography.bodySize, weight: weight))
        }

        let footer = label(content.footerText, size: AboutTypography.footerSize, weight: .semibold, color: .secondaryLabelColor)

        addSubview(topPanel)
        addSubview(mainStack)
        addSubview(bottomPanel)
        bottomPanel.addSubview(footer)

        mainStack.addArrangedSubview(iconView)
        mainStack.addArrangedSubview(appName)
        mainStack.addArrangedSubview(version)
        mainStack.addArrangedSubview(spacer(height: 8))
        mainStack.addArrangedSubview(headline)
        mainStack.addArrangedSubview(subheadline)
        mainStack.addArrangedSubview(spacer(height: 18))
        mainStack.addArrangedSubview(copyright)
        mainStack.addArrangedSubview(spacer(height: 14))
        mainStack.addArrangedSubview(developerLabel)
        mainStack.addArrangedSubview(developerName)
        mainStack.addArrangedSubview(affiliations)

        NSLayoutConstraint.activate([
            topPanel.topAnchor.constraint(equalTo: topAnchor),
            topPanel.leadingAnchor.constraint(equalTo: leadingAnchor),
            topPanel.trailingAnchor.constraint(equalTo: trailingAnchor),
            topPanel.heightAnchor.constraint(equalToConstant: 160),

            bottomPanel.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomPanel.heightAnchor.constraint(equalToConstant: 64),

            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 34),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomPanel.topAnchor, constant: -18),

            iconView.widthAnchor.constraint(equalToConstant: 104),
            iconView.heightAnchor.constraint(equalToConstant: 104),

            footer.centerXAnchor.constraint(equalTo: bottomPanel.centerXAnchor),
            footer.centerYAnchor.constraint(equalTo: bottomPanel.centerYAnchor),
            footer.leadingAnchor.constraint(greaterThanOrEqualTo: bottomPanel.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: bottomPanel.trailingAnchor, constant: -24)
        ])
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func spacer(height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
