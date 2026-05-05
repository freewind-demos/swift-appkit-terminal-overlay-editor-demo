import AppKit

@MainActor
final class EditorOverlayView: NSView {
    private let fileLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    let textView = NSTextView(frame: .zero)

    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    var text: String {
        textView.string
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func configure(fileURL: URL, text: String, isNewFile: Bool) {
        fileLabel.stringValue = fileURL.path
        statusLabel.stringValue = isNewFile ? "New file" : "Existing file"
        textView.string = text
    }

    func setStatus(_ status: String) {
        statusLabel.stringValue = status
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        fileLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.textColor = .secondaryLabelColor

        saveButton.target = self
        saveButton.action = #selector(handleSave)
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]

        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.keyEquivalent = "w"
        closeButton.keyEquivalentModifierMask = [.command]

        textView.isRichText = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.allowsUndo = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        let topBar = NSStackView(views: [fileLabel, statusLabel, saveButton, closeButton])
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.distribution = .fill
        topBar.spacing = 12

        addSubview(topBar)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc
    private func handleSave() {
        onSave?()
    }

    @objc
    private func handleClose() {
        onClose?()
    }
}
