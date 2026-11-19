import AppKit
import WebKit
import UniformTypeIdentifiers
import AVFoundation
import Speech
import CoreImage

final class LiquidGlassSurfaceView: NSVisualEffectView {
    private let borderAlpha: CGFloat
    private let customTintColor: NSColor?
    private let customBorderColor: NSColor?

    init(
        cornerRadius: CGFloat,
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        borderAlpha: CGFloat = 0.20,
        tintColor: NSColor? = nil,
        borderColorOverride: NSColor? = nil
    ) {
        self.borderAlpha = borderAlpha
        self.customTintColor = tintColor
        self.customBorderColor = borderColorOverride
        super.init(frame: .zero)
        self.material = material
        self.blendingMode = blendingMode
        self.state = .active
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        if let customTintColor {
            layer?.backgroundColor = customTintColor.cgColor
        }
        updateSpecularStroke()
    }

    required init?(coder: NSCoder) {
        self.borderAlpha = 0.20
        self.customTintColor = nil
        self.customBorderColor = nil
        super.init(coder: coder)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSpecularStroke()
    }

    private func updateSpecularStroke() {
        if let customBorderColor {
            layer?.borderColor = customBorderColor.cgColor
            return
        }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let strokeColor = isDark
            ? NSColor.white.withAlphaComponent(borderAlpha)
            : NSColor.black.withAlphaComponent(min(borderAlpha * 0.65, 0.14))
        layer?.borderColor = strokeColor.cgColor
    }
}

final class FlippedListDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class SpaceLensOrbitBackdropView: NSView {
    private let ambientGlowLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupAmbientGlow()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupAmbientGlow()
    }

    private func setupAmbientGlow() {
        ambientGlowLayer.type = .radial
        ambientGlowLayer.colors = [
            NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.95, alpha: 0.22).cgColor,
            NSColor(calibratedRed: 0.35, green: 0.40, blue: 0.85, alpha: 0.10).cgColor,
            NSColor(calibratedRed: 0.075, green: 0.051, blue: 0.141, alpha: 0.0).cgColor,
        ]
        ambientGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        ambientGlowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer?.insertSublayer(ambientGlowLayer, at: 0)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.55
        pulse.toValue = 1.0
        pulse.duration = 4.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ambientGlowLayer.add(pulse, forKey: "ambientBreathing")
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height) * 0.95
        ambientGlowLayer.frame = CGRect(
            x: bounds.midX - side / 2.0,
            y: bounds.midY - side / 2.0,
            width: side,
            height: side
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Glow radial lembut di belakang node pusat Space Lens
        let glowColors: [CGColor] = [
            NSColor(calibratedRed: 0.49, green: 0.43, blue: 0.82, alpha: 0.14).cgColor,
            NSColor(calibratedRed: 0.30, green: 0.39, blue: 0.72, alpha: 0.07).cgColor,
            NSColor(calibratedRed: 0.075, green: 0.051, blue: 0.141, alpha: 0.0).cgColor,
        ]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0.0, 0.45, 1.0]) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 12,
                endCenter: center,
                endRadius: min(bounds.width, bounds.height) * 0.49,
                options: []
            )
        }

        // 3 cincin orbit konsentris tipis ala CleanMyMac Space Lens
        let ringSpecs: [(CGFloat, CGFloat)] = [
            (92.0, 0.085),
            (148.0, 0.060),
            (198.0, 0.042),
        ]
        ctx.saveGState()
        for (radius, alpha) in ringSpecs {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha * 0.72).cgColor)
            ctx.setLineWidth(1.0)
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2.0,
                height: radius * 2.0
            )
            ctx.strokeEllipse(in: rect)
        }

        // 6 garis penghubung heksagonal & titik cahaya persimpangan pada cincin dalam
        let anglesDeg: [CGFloat] = [90, 30, -30, -90, -150, 150]
        let spokeInnerR: CGFloat = 72.0
        let spokeOuterR: CGFloat = 148.0
        let junctionR: CGFloat = 92.0

        for deg in anglesDeg {
            let rad = deg * .pi / 180.0
            let cosA = cos(rad)
            let sinA = sin(rad)

            let startPt = CGPoint(x: center.x + spokeInnerR * cosA, y: center.y + spokeInnerR * sinA)
            let endPt = CGPoint(x: center.x + spokeOuterR * cosA, y: center.y + spokeOuterR * sinA)

            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.11).cgColor)
            ctx.setLineWidth(1.0)
            ctx.move(to: startPt)
            ctx.addLine(to: endPt)
            ctx.strokePath()

            let dotCenter = CGPoint(x: center.x + junctionR * cosA, y: center.y + junctionR * sinA)
            ctx.setFillColor(NSColor(calibratedRed: 0.65, green: 0.56, blue: 0.99, alpha: 0.34).cgColor)
            ctx.fillEllipse(in: CGRect(x: dotCenter.x - 5.0, y: dotCenter.y - 5.0, width: 10.0, height: 10.0))

            ctx.setFillColor(NSColor(calibratedRed: 0.86, green: 0.82, blue: 1.0, alpha: 0.90).cgColor)
            ctx.fillEllipse(in: CGRect(x: dotCenter.x - 2.2, y: dotCenter.y - 2.2, width: 4.4, height: 4.4))
        }
        ctx.restoreGState()
    }
}

final class GradientPillButton: NSButton {
    private let gradientLayer = CAGradientLayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false
    private let label: NSTextField

    init(
        title: String,
        target: AnyObject?,
        action: Selector?,
        colors: [NSColor] = [
            NSColor(calibratedRed: 0.48, green: 0.40, blue: 0.82, alpha: 1.0),
            NSColor(calibratedRed: 0.34, green: 0.43, blue: 0.83, alpha: 1.0),
        ],
        cornerRadius: CGFloat = 12
    ) {
        self.label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        self.title = ""
        self.target = target
        self.action = action
        self.isBordered = false
        self.setButtonType(.momentaryPushIn)
        self.wantsLayer = true
        self.layer?.cornerRadius = cornerRadius
        if #available(macOS 10.15, *) {
            self.layer?.cornerCurve = .continuous
        }
        self.layer?.masksToBounds = false
        self.layer?.shadowColor = NSColor(calibratedRed: 0.48, green: 0.40, blue: 0.82, alpha: 0.42).cgColor
        self.layer?.shadowRadius = 9
        self.layer?.shadowOpacity = 0.48
        self.layer?.shadowOffset = CGSize(width: 0, height: -2)

        gradientLayer.colors = colors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        gradientLayer.cornerRadius = cornerRadius
        if #available(macOS 10.15, *) {
            gradientLayer.cornerCurve = .continuous
        }
        gradientLayer.masksToBounds = true
        self.layer?.insertSublayer(gradientLayer, at: 0)

        label.font = .systemFont(ofSize: 13.5, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.55
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        return bounds.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    private func applyScale(_ s: CGFloat) {
        let midX = bounds.midX
        let midY = bounds.midY
        var t = CATransform3DMakeTranslation(midX, midY, 0)
        t = CATransform3DScale(t, s, s, 1.0)
        t = CATransform3DTranslate(t, -midX, -midY, 0)
        self.layer?.transform = t
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isEnabled else { return }
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(1.035)
            self.layer?.shadowRadius = 15
            self.layer?.shadowOpacity = 0.75
            self.label.layer?.transform = CATransform3DMakeTranslation(2.5, 0, 0)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(1.0)
            self.layer?.shadowRadius = 9
            self.layer?.shadowOpacity = 0.48
            self.label.layer?.transform = CATransform3DIdentity
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            applyScale(0.95)
        }
        super.mouseDown(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(self.isHovered ? 1.035 : 1.0)
        }
    }
}

final class InteractiveDarkGlassPillButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false

    init(
        title: String,
        target: AnyObject?,
        action: Selector,
        fontSize: CGFloat = 11.5,
        height: CGFloat = 30
    ) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.isBordered = false
        self.setButtonType(.momentaryPushIn)
        self.font = .systemFont(ofSize: fontSize, weight: .semibold)
        self.contentTintColor = .white
        self.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor(calibratedRed: 0.94, green: 0.92, blue: 1.0, alpha: 0.96),
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            ]
        )
        self.wantsLayer = true
        self.layer?.cornerRadius = height >= 30 ? 9 : 8
        if #available(macOS 10.15, *) {
            self.layer?.cornerCurve = .continuous
        }
        self.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.21, alpha: 0.94).cgColor
        self.layer?.borderWidth = 1
        self.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        self.layer?.shadowColor = NSColor(calibratedRed: 0.49, green: 0.43, blue: 0.82, alpha: 0.5).cgColor
        self.layer?.shadowRadius = 6
        self.layer?.shadowOpacity = 0.0
        self.layer?.shadowOffset = CGSize(width: 0, height: -1)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func applyScale(_ s: CGFloat) {
        let midX = bounds.midX
        let midY = bounds.midY
        var t = CATransform3DMakeTranslation(midX, midY, 0)
        t = CATransform3DScale(t, s, s, 1.0)
        t = CATransform3DTranslate(t, -midX, -midY, 0)
        self.layer?.transform = t
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(1.03)
            layer?.backgroundColor = NSColor(calibratedRed: 0.22, green: 0.20, blue: 0.35, alpha: 0.96).cgColor
            layer?.borderColor = NSColor(calibratedRed: 0.67, green: 0.62, blue: 0.91, alpha: 0.45).cgColor
            layer?.shadowOpacity = 0.40
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(1.0)
            layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.21, alpha: 0.94).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
            layer?.shadowOpacity = 0.0
        }
    }

    override func mouseDown(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            applyScale(0.96)
        }
        super.mouseDown(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(self.isHovered ? 1.03 : 1.0)
        }
    }
}

final class WorkspaceRowButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false
    var isCurrentSelected: Bool = false {
        didSet {
            updateVisualState(animated: true)
        }
    }

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let tagField = NSTextField(labelWithString: "")
    private var contentLeadingConstraint: NSLayoutConstraint?

    init(
        title: String,
        tagText: String,
        symbol: String,
        index: Int,
        isSelected: Bool,
        target: AnyObject?,
        action: Selector?
    ) {
        self.isCurrentSelected = isSelected
        super.init(frame: .zero)
        self.title = ""
        self.target = target
        self.action = action
        self.tag = index
        self.toolTip = "Pilih ruang kerja \(title)"
        self.isBordered = false
        self.setButtonType(.momentaryPushIn)
        self.wantsLayer = true
        self.layer?.cornerRadius = 9
        if #available(macOS 10.15, *) {
            self.layer?.cornerCurve = .continuous
        }
        setupViews(title: title, tagText: tagText, symbol: symbol)
        updateVisualState(animated: false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setupViews(title: String, tagText: String, symbol: String) {
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameField.stringValue = title
        nameField.font = .systemFont(ofSize: 12, weight: isCurrentSelected ? .bold : .medium)
        nameField.textColor = .white
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false

        tagField.stringValue = "  \(tagText)  "
        tagField.font = .systemFont(ofSize: 10, weight: .semibold)
        tagField.wantsLayer = true
        tagField.layer?.cornerRadius = 6
        if #available(macOS 10.15, *) {
            tagField.layer?.cornerCurve = .continuous
        }
        tagField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameField)
        addSubview(tagField)

        let lead = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        self.contentLeadingConstraint = lead

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            lead,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: tagField.leadingAnchor, constant: -6),
            tagField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            tagField.centerYAnchor.constraint(equalTo: centerYAnchor),
            tagField.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    func updateVisualState(animated: Bool = true) {
        let block = {
            if self.isCurrentSelected {
                self.layer?.backgroundColor = NSColor(calibratedRed: 0.30, green: 0.27, blue: 0.48, alpha: 0.88).cgColor
                self.layer?.borderWidth = 1.0
                self.layer?.borderColor = NSColor(calibratedRed: 0.67, green: 0.62, blue: 0.91, alpha: 0.48).cgColor
                self.iconView.contentTintColor = .white
                self.nameField.font = .systemFont(ofSize: 12, weight: .bold)
                self.tagField.textColor = .white
                self.tagField.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
            } else if self.isHovered {
                self.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
                self.layer?.borderWidth = 0.5
                self.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
                self.iconView.contentTintColor = .white
                self.nameField.font = .systemFont(ofSize: 12, weight: .semibold)
                self.tagField.textColor = .white
                self.tagField.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            } else {
                self.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
                self.layer?.borderWidth = 0.5
                self.layer?.borderColor = NSColor.white.withAlphaComponent(0.065).cgColor
                self.iconView.contentTintColor = NSColor(calibratedRed: 0.67, green: 0.70, blue: 0.82, alpha: 0.92)
                self.nameField.font = .systemFont(ofSize: 12, weight: .medium)
                self.tagField.textColor = NSColor(calibratedRed: 0.67, green: 0.69, blue: 0.78, alpha: 0.90)
                self.tagField.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
            }

            let targetOffset: CGFloat = self.isHovered ? 13.5 : 10.0
            self.contentLeadingConstraint?.constant = targetOffset
            self.layoutSubtreeIfNeeded()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                block()
            }
        } else {
            block()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateVisualState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateVisualState(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.layer?.transform = CATransform3DMakeScale(0.98, 0.98, 1.0)
        }
        super.mouseDown(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            self.layer?.transform = CATransform3DIdentity
        }
    }
}

final class SpaceLensBubbleButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false
    private let accent: NSColor
    private let isHighlightedNode: Bool
    private let diameter: CGFloat
    private let contentStack: NSStackView
    private let iconView: NSImageView
    private let nameLabel: NSTextField
    private let subLabel: NSTextField

    init(
        title: String,
        subtitle: String,
        symbol: String,
        diameter: CGFloat,
        isHighlighted: Bool,
        tag: Int,
        accentColor: NSColor,
        target: AnyObject?,
        action: Selector?
    ) {
        self.accent = accentColor
        self.isHighlightedNode = isHighlighted
        self.diameter = diameter

        self.iconView = NSImageView()
        self.nameLabel = NSTextField(labelWithString: title)
        self.subLabel = NSTextField(labelWithString: subtitle)
        self.contentStack = NSStackView(views: [iconView, nameLabel, subLabel])

        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        self.title = ""
        self.target = target
        self.action = action
        self.tag = tag
        self.toolTip = "Buka Workspace \(title) (\(subtitle))"
        self.isBordered = false
        self.setButtonType(.momentaryPushIn)
        self.wantsLayer = true
        self.layer?.cornerRadius = diameter / 2.0
        self.layer?.masksToBounds = false
        self.layer?.borderWidth = isHighlighted ? 1.8 : 1.3
        self.layer?.borderColor = accent.withAlphaComponent(isHighlighted ? 0.92 : 0.68).cgColor
        self.layer?.backgroundColor = accent
            .blended(withFraction: isHighlighted ? 0.82 : 0.88, of: NSColor(calibratedRed: 0.055, green: 0.063, blue: 0.106, alpha: 1.0))?
            .withAlphaComponent(isHighlighted ? 0.88 : 0.84)
            .cgColor
        self.layer?.shadowColor = accent.withAlphaComponent(0.36).cgColor
        self.layer?.shadowRadius = isHighlighted ? 14 : 9
        self.layer?.shadowOpacity = isHighlighted ? 0.38 : 0.20
        self.layer?.shadowOffset = .zero

        setupContent(title: title, subtitle: subtitle, symbol: symbol)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent(title: String, subtitle: String, symbol: String) {
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.contentTintColor = isHighlightedNode
            ? NSColor.white
            : accent.blended(withFraction: 0.55, of: .white) ?? NSColor.white
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: diameter >= 130 ? 27 : 21,
            weight: .semibold
        )
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: diameter >= 130 ? 13.5 : 11.5, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail

        subLabel.font = .systemFont(ofSize: diameter >= 130 ? 10.5 : 9.0, weight: .medium)
        subLabel.textColor = NSColor.white.withAlphaComponent(0.84)
        subLabel.alignment = .center

        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 3
        contentStack.wantsLayer = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: diameter - 20),
        ])
    }

    func startFloatingAnimation(phase: Double) {
        let floatAnim = CAKeyframeAnimation(keyPath: "transform.translation.y")
        let amplitude: CGFloat = isHighlightedNode ? 2.0 : 3.0
        floatAnim.values = [0.0, -amplitude, 0.0, amplitude, 0.0]
        floatAnim.keyTimes = [0, 0.25, 0.5, 0.75, 1.0]
        floatAnim.duration = 4.2 + (Double(tag % 5) * 0.45)
        floatAnim.timeOffset = phase * 0.6
        floatAnim.repeatCount = .infinity
        floatAnim.isRemovedOnCompletion = false
        floatAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        contentStack.layer?.add(floatAnim, forKey: "celestialDrift")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        let localPoint = convert(point, from: superview)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = localPoint.x - center.x
        let dy = localPoint.y - center.y
        let r = diameter / 2.0
        return (dx * dx + dy * dy <= r * r) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    private func applyScale(_ s: CGFloat) {
        let midX = bounds.midX
        let midY = bounds.midY
        var t = CATransform3DMakeTranslation(midX, midY, 0)
        t = CATransform3DScale(t, s, s, 1.0)
        t = CATransform3DTranslate(t, -midX, -midY, 0)
        self.layer?.transform = t
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isEnabled else { return }
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(isHighlightedNode ? 1.06 : 1.09)
            layer?.borderColor = accent.withAlphaComponent(0.98).cgColor
            layer?.borderWidth = isHighlightedNode ? 2.5 : 2.0
            layer?.shadowRadius = isHighlightedNode ? 22 : 16
            layer?.shadowOpacity = isHighlightedNode ? 0.68 : 0.48
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(1.0)
            layer?.borderColor = accent.withAlphaComponent(isHighlightedNode ? 0.92 : 0.68).cgColor
            layer?.borderWidth = isHighlightedNode ? 1.8 : 1.3
            layer?.shadowRadius = isHighlightedNode ? 14 : 9
            layer?.shadowOpacity = isHighlightedNode ? 0.38 : 0.20
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            applyScale(0.94)
        }
        super.mouseDown(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(self.isHovered ? (self.isHighlightedNode ? 1.06 : 1.09) : 1.0)
        }
    }
}

final class InteractivePreviewThumbnailView: NSView {
    private var trackingArea: NSTrackingArea?
    private var isHovered: Bool = false
    let imageView = NSImageView()

    var image: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    var imageScaling: NSImageScaling {
        get { imageView.imageScaling }
        set { imageView.imageScaling = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 10
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.05, blue: 0.20, alpha: 1).cgColor
        layer?.shadowColor = NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.95, alpha: 0.5).cgColor
        layer?.shadowRadius = 8
        layer?.shadowOpacity = 0.0
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 9
        if #available(macOS 10.15, *) {
            imageView.layer?.cornerCurve = .continuous
        }
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func applyScale(_ s: CGFloat) {
        let midX = bounds.midX
        let midY = bounds.midY
        var t = CATransform3DMakeTranslation(midX, midY, 0)
        t = CATransform3DScale(t, s, s, 1.0)
        t = CATransform3DTranslate(t, -midX, -midY, 0)
        self.layer?.transform = t
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(1.045)
            layer?.borderColor = NSColor(calibratedRed: 0.65, green: 0.56, blue: 0.99, alpha: 0.85).cgColor
            layer?.borderWidth = 1.5
            layer?.shadowOpacity = 0.55
            layer?.shadowRadius = 14
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyScale(1.0)
            layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            layer?.borderWidth = 1.0
            layer?.shadowOpacity = 0.0
            layer?.shadowRadius = 8
        }
    }
}

final class ModelDropView: NSView {
    var onDrop: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard droppedModelURL(from: sender) != nil else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedModelURL(from: sender) else { return false }
        onDrop?(url)
        return true
    }

    private func droppedModelURL(from sender: NSDraggingInfo) -> URL? {
        guard let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ), let url = objects.first as? URL, url.pathExtension.lowercased() == "litertlm" else {
            return nil
        }
        return url
    }
}

final class WindowResizeHandleView: NSView {
    enum Edge {
        case leading
        case trailing
    }

    private let edge: Edge
    private var startingWindowFrame: NSRect?
    private var startingMouseX: CGFloat?

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startingWindowFrame = window.frame
        startingMouseX = NSEvent.mouseLocation.x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let startingWindowFrame,
              let startingMouseX,
              let screen = window.screen ?? NSScreen.main else {
            return
        }

        let viewport = screen.visibleFrame
        let minimumWidth = viewport.width * 0.5
        let maximumWidth = viewport.width
        let deltaX = NSEvent.mouseLocation.x - startingMouseX
        var resizedFrame = startingWindowFrame

        switch edge {
        case .leading:
            let proposedMinX = startingWindowFrame.minX + deltaX
            let minimumX = max(viewport.minX, startingWindowFrame.maxX - maximumWidth)
            let maximumX = min(viewport.maxX - minimumWidth, startingWindowFrame.maxX - minimumWidth)
            resizedFrame.origin.x = min(max(proposedMinX, minimumX), maximumX)
            resizedFrame.size.width = startingWindowFrame.maxX - resizedFrame.minX
        case .trailing:
            let proposedMaxX = startingWindowFrame.maxX + deltaX
            let minimumX = max(viewport.minX + minimumWidth, startingWindowFrame.minX + minimumWidth)
            let maximumX = min(viewport.maxX, startingWindowFrame.minX + maximumWidth)
            let maxX = min(max(proposedMaxX, minimumX), maximumX)
            resizedFrame.size.width = maxX - startingWindowFrame.minX
        }

        window.setFrame(resizedFrame, display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        startingWindowFrame = nil
        startingMouseX = nil
    }
}

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

final class WindowDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, URLSessionTaskDelegate {
    private let appName = "EduVis AI Gallery"

    private struct AppView {
        let title: String
        let path: String
    }

    private let appViews = [
        AppView(title: "Utama", path: "utama.html"),
        AppView(title: "Utama V2", path: "utamaV2.html"),
        AppView(title: "TTS Studio AI", path: "tts_studio_lokal.html"),
        AppView(title: "VS", path: "VS.html"),
        AppView(title: "Claude", path: "claude.html"),
        AppView(title: "EduVis", path: "eduVis.html"),
        AppView(title: "EduVis Live", path: "gemini_live.html"),
        AppView(title: "EduVis Live Futuristik", path: "gemini_live_futuristik.html"),
        AppView(title: "Liquid Chatbot", path: "liquid_chatbot.html"),
        AppView(title: "Aurora", path: "aurora.html"),
        AppView(title: "Tanya AI", path: "tanya-ai-standalone.html"),
        AppView(title: "Vision Ulti", path: "vision_ulti.html"),
        AppView(title: "Analisis Kode", path: "analisis-kode.html"),
        AppView(title: "Agen AI Otonom", path: "agen-ai-otonom.html"),
        AppView(title: "PGlite Vector SQL", path: "mesin-pglite-rag.html"),
    ]

    private var window: NSWindow!
    private var webView: WKWebView!
    private var launcherView: NSView!
    private var webContainer: NSView!
    private var webContentArea: NSView!
    private var navigationBar: NSVisualEffectView!
    private var webTitle: NSTextField!
    private var toolbarModelBadge: NSTextField?
    private var toolbarWorkspacePicker: NSPopUpButton?
    private var toolbarLeftPill: NSVisualEffectView?
    private var toolbarCenterPill: NSVisualEffectView?
    private var toolbarRightPill: NSVisualEffectView?
    private var toolbarSeparator: NSView?
    private var reloadButton: NSButton!
    private var viewPicker: NSPopUpButton!
    private var launchButton: NSButton!
    private var launchButtonGradient: CAGradientLayer?
    private var startupStatus: NSTextField!
    private var launcherSelectedSummary: NSTextField?
    private var launcherFileBadge: NSTextField?
    private var launcherModelPillBadge: NSTextField?
    private var workspaceRowButtons: [NSButton] = []
    private var lanQRPanel: NSPanel?
    private var lanQRURLField: NSTextField?
    private var lanQRImageView: NSImageView?
    private var lanQRStatusLabel: NSTextField?
    private var lanQRAddresses: [String] = []
    private var lanQRAddressPicker: NSPopUpButton?
    private var baseURL: URL!
    private var bannerPath: String?
    private var webConfiguration: WKWebViewConfiguration!
    private var workspaceWebViews: [String: WKWebView] = [:]
    private var statusItem: NSStatusItem?
    private var readinessPath: String?
    private var readinessTimer: Timer?
    private var selectedModelID: String?
    private var terminalApplication: NSRunningApplication?
    private var audioEngine: AVAudioEngine?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var speechSilenceTimer: Timer?
    private var lastSpeechTranscription: String = ""
    private var speechGeneration = 0
    private var backendProcess: Process?
    private var backendLogHandle: FileHandle?
    private var standaloneMode = false
    private var isTerminatingApp = false
    private var modelPanel: NSPanel?
    private var aboutPanel: NSPanel?
    private var quickAskPanel: NSPanel?
    private var quickAskInput: NSTextField?
    private var quickAskAnswerView: NSTextView?
    private var quickAskStatusLabel: NSTextField?
    private var quickAskSendButton: NSButton?
    private var litertMemoryMB: Double = 0
    private var backendMemoryMB: Double = 0
    private var memoryTimer: Timer?
    private var modelPicker: NSPopUpButton!
    private var modelStatus: NSTextField!
    private var modelIDField: NSTextField!
    private var modelImportButton: NSButton!
    private var modelDropView: ModelDropView!
    private var modelInspectSummaries: [String: String] = [:]
    private var litertRuntimeVersion: String?
    private lazy var modelSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func applicationShouldSaveApplicationState(_ app: NSApplication, to coder: NSCoder) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication, from coder: NSCoder) -> Bool {
        false
    }

    private func loadCustomAppIcon() -> NSImage? {
        if let pngURL = Bundle.main.url(forResource: "app_icon", withExtension: "png"),
           let img = NSImage(contentsOf: pngURL) {
            return img
        }
        if let icnsURL = Bundle.main.url(forResource: "EduVisAIGallery", withExtension: "icns"),
           let img = NSImage(contentsOf: icnsURL) {
            return img
        }
        if let projectURL = resolveStandaloneProjectURL() {
            let candidate = projectURL.appendingPathComponent("nano_asset/app_icon.png")
            if let img = NSImage(contentsOf: candidate) {
                return img
            }
        }
        return nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = loadCustomAppIcon() {
            NSApp.applicationIconImage = icon
            NSWorkspace.shared.setIcon(icon, forFile: Bundle.main.bundlePath, options: [])
        } else {
            NSLog("Ikon EduVis AI Gallery tidak ditemukan di dalam bundle aplikasi.")
        }
        if CommandLine.arguments.count > 1,
           let url = URL(string: CommandLine.arguments[1]) {
            baseURL = url
            if CommandLine.arguments.count > 2 {
                bannerPath = CommandLine.arguments[2]
            }
            if CommandLine.arguments.count > 3 {
                readinessPath = CommandLine.arguments[3]
            }
        } else if !startStandaloneBackend() {
            NSLog("Tidak dapat memulai backend EduVis AI Gallery.")
            NSApp.terminate(nil)
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.preferences.setValue(true, forKey: "speechRecognitionEnabled")
        configuration.preferences.setValue(true, forKey: "mediaDevicesEnabled")
        configuration.preferences.setValue(false, forKey: "mediaCaptureRequiresSecureConnection")
        let weakHandler = WeakScriptMessageHandler(delegate: self)
        configuration.userContentController.add(weakHandler, name: "appTheme")
        configuration.userContentController.add(weakHandler, name: "savePng")
        configuration.userContentController.add(weakHandler, name: "saveSvg")
        configuration.userContentController.add(weakHandler, name: "saveDocument")
        configuration.userContentController.add(weakHandler, name: "nativeSpeech")
        configuration.userContentController.add(weakHandler, name: "aiStatus")
        configuration.userContentController.add(weakHandler, name: "openExternal")
        configuration.userContentController.addUserScript(WKUserScript(
            source: "document.documentElement.classList.add('macos-native');",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // Muat gaya chat khas macOS di SEMUA workspace (idempotent). Semua aturannya
        // di-scope ke html.macos-native, jadi klien browser tidak terpengaruh.
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
                const existing = document.querySelector('link[href*="native-mac.css"]');
                if (existing) existing.remove();
                const link = document.createElement('link');
                link.rel = 'stylesheet';
                link.href = '/nano_asset/assets/css/native-mac.css?v=11';
                link.setAttribute('data-native-mac', '1');
                (document.body || document.documentElement).appendChild(link);

                if (!document.querySelector('script[src*="eduvis-liquid-engine.js"]')) {
                    const lgScript = document.createElement('script');
                    lgScript.src = '/nano_asset/assets/js/eduvis-liquid-engine.js?v=1';
                    lgScript.defer = true;
                    lgScript.setAttribute('data-eduvis-liquid-engine', '1');
                    (document.head || document.documentElement).appendChild(lgScript);
                }

                try {
                    localStorage.removeItem('gemma_chat_font_size_minimized');
                } catch (_) {}
                if (!document.querySelector('script[src*="chat-font-size.js"]')) {
                    const fsScript = document.createElement('script');
                    fsScript.src = '/nano_asset/assets/js/chat-font-size.js?v=2';
                    fsScript.defer = true;
                    fsScript.setAttribute('data-chat-font-size', '1');
                    (document.head || document.documentElement).appendChild(fsScript);
                }
                if (typeof window.expandChatFontSizeWidget === 'function') {
                    window.expandChatFontSizeWidget();
                } else {
                    document.getElementById('gfc-pill')?.classList.remove('gfc-minimized');
                }
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
                const reportTheme = () => {
                    if (!document.body) return;
                    const isLight = document.body.classList.contains('light-theme') ||
                        document.documentElement.getAttribute('data-theme') === 'light';
                    const theme = isLight ? 'light' : 'dark';
                    window.webkit?.messageHandlers?.appTheme?.postMessage(theme);
                };
                reportTheme();
                if (document.body) {
                    new MutationObserver(reportTheme).observe(document.body, {
                        attributes: true,
                        attributeFilter: ['class']
                    });
                }
                new MutationObserver(reportTheme).observe(document.documentElement, {
                    attributes: true,
                    attributeFilter: ['data-theme']
                });
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
                document.documentElement.classList.add('macos-native');
                const style = document.createElement('style');
                style.textContent = `
                    html.macos-native body {
                        --mac-window-bg: #180b38;
                        --mac-window-fg: #f8f5ff;
                        --mac-surface: rgba(54, 29, 108, 0.84);
                        --mac-surface-subtle: rgba(42, 21, 86, 0.78);
                        --mac-border: rgba(236, 72, 153, 0.24);
                        background: radial-gradient(circle at 78% 28%, rgba(236, 72, 153, 0.16) 0%, transparent 50%), linear-gradient(135deg, #160934 0%, #241154 54%, #120729 100%) !important;
                        color: var(--mac-window-fg) !important;
                    }
                    html.macos-native body.light-theme,
                    html.macos-native[data-theme="light"] body {
                        --mac-window-bg: #f8f7ff;
                        --mac-window-fg: #1e1b4b;
                        --mac-surface: rgba(255, 255, 255, 0.92);
                        --mac-surface-subtle: rgba(242, 239, 255, 0.85);
                        --mac-border: rgba(124, 58, 237, 0.16);
                    }
                    html.macos-native body:not(.light-theme) #chat-area,
                    html.macos-native body.light-theme #chat-area {
                        background: var(--mac-window-bg) !important;
                    }
                    html.macos-native #messages,
                    html.macos-native #chatArea,
                    html.macos-native .thread {
                        background: transparent !important;
                    }
                    html.macos-native #initial-placeholder .suggestion-card {
                        border: 1px solid var(--mac-border) !important;
                        border-radius: 16px !important;
                        background: var(--mac-surface-subtle) !important;
                        backdrop-filter: blur(24px) saturate(190%) !important;
                        -webkit-backdrop-filter: blur(24px) saturate(190%) !important;
                        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.16), 0 8px 20px rgba(0, 0, 0, 0.14) !important;
                    }
                    html.macos-native #drop-zone {
                        border: 1px solid var(--mac-border) !important;
                        border-radius: 22px !important;
                        background: var(--mac-surface) !important;
                        backdrop-filter: blur(30px) saturate(200%) !important;
                        -webkit-backdrop-filter: blur(30px) saturate(200%) !important;
                        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.2), 0 14px 34px rgba(0, 0, 0, 0.2) !important;
                    }
                    html.macos-native .sparkle-text {
                        color: var(--mac-window-fg) !important;
                        -webkit-text-fill-color: var(--mac-window-fg) !important;
                    }
                    html.macos-native .mermaid-wrapper {
                        display: block !important;
                        width: 100% !important;
                    }
                    html.macos-native .mermaid-svg-container {
                        display: block !important;
                        height: auto !important;
                        min-height: 200px;
                    }
                    html.macos-native .mermaid-content {
                        display: block !important;
                        width: 100% !important;
                        height: auto !important;
                        min-height: 0 !important;
                    }
                    html.macos-native .mermaid-content svg,
                    html.macos-native #messages .mermaid > svg {
                        display: block !important;
                        width: 100% !important;
                        max-width: 100% !important;
                        height: auto !important;
                        margin-inline: auto;
                    }
                    html.macos-native #messages > div,
                    html.macos-native .chat-bubble-ai,
                    html.macos-native .table-wrapper,
                    html.macos-native .table-wrap,
                    html.macos-native .table-container {
                        min-width: 0 !important;
                        max-width: 100% !important;
                    }
                    html.macos-native .table-wrapper,
                    html.macos-native .table-wrap,
                    html.macos-native .table-container {
                        display: block !important;
                        width: 100% !important;
                        max-width: 100% !important;
                        overflow-x: auto !important;
                        -webkit-overflow-scrolling: touch !important;
                        overscroll-behavior-x: contain !important;
                    }
                `;
                document.head.append(style);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        self.webConfiguration = configuration

        let rootView = NSView()
        launcherView = makeLauncherView()
        webContainer = makeWebContainer()
        webContainer.isHidden = true
        webView = getOrCreateWebView(for: appViews[0])
        setupStatusItem()
        setupMainMenu()
        rootView.addSubview(launcherView)
        rootView.addSubview(webContainer)
        let contentViews: [NSView] = [launcherView, webContainer]
        for view in contentViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
                view.topAnchor.constraint(equalTo: rootView.topAnchor),
                view.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            ])
        }
        let leadingResizeHandle = WindowResizeHandleView(edge: .leading)
        let trailingResizeHandle = WindowResizeHandleView(edge: .trailing)
        for (handle, isLeading) in [(leadingResizeHandle, true), (trailingResizeHandle, false)] {
            handle.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview(handle)
            NSLayoutConstraint.activate([
                handle.widthAnchor.constraint(equalToConstant: 12),
                handle.topAnchor.constraint(equalTo: rootView.topAnchor),
                handle.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
                isLeading
                    ? handle.leadingAnchor.constraint(equalTo: rootView.leadingAnchor)
                    : handle.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            ])
        }

        let screen = NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 850)
        let initialFrameSize = NSSize(
            width: visibleFrame.width * 0.8,
            height: visibleFrame.height * 0.85
        )
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialFrameSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isRestorable = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        configureWindowSizeLimits(for: visibleFrame)
        let initialFrame = NSRect(
            x: visibleFrame.midX - initialFrameSize.width / 2,
            y: visibleFrame.midY - initialFrameSize.height / 2,
            width: initialFrameSize.width,
            height: initialFrameSize.height
        )
        window.setFrame(initialFrame, display: false)
        window.title = appName
        window.delegate = self
        window.contentView = rootView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.servicesProvider = self

        if CommandLine.arguments.contains("--hide-terminal"),
           let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first {
            terminalApplication = terminal
            terminal.hide()
        }
        updateStartupStatus()
        readinessTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.updateStartupStatus()
        }
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.refreshMemoryStats()
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let screen = sender.screen else { return frameSize }
        let viewport = screen.visibleFrame.size
        return NSSize(
            width: min(max(frameSize.width, viewport.width * 0.5), viewport.width),
            height: min(max(frameSize.height, viewport.height * 0.5), viewport.height)
        )
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let screen = window.screen else {
            return
        }
        configureWindowSizeLimits(for: screen.visibleFrame)
    }

    private func configureWindowSizeLimits(for viewport: NSRect) {
        window.minSize = NSSize(width: viewport.width * 0.5, height: viewport.height * 0.5)
        window.maxSize = viewport.size
    }

    private func resolveStandaloneProjectURL() -> URL? {
        let fm = FileManager.default
        if let info = Bundle.main.infoDictionary,
           let projectDirectory = info["EduVisProjectDirectory"] as? String {
            let candidate = URL(fileURLWithPath: projectDirectory, isDirectory: true)
            if fm.fileExists(atPath: candidate.appendingPathComponent("gemma_chat_gui.py").path) {
                return candidate
            }
        }
        if let bundledAppDir = Bundle.main.resourceURL?.appendingPathComponent("app", isDirectory: true),
           fm.fileExists(atPath: bundledAppDir.appendingPathComponent("gemma_chat_gui.py").path) {
            return bundledAppDir
        }
        return nil
    }

    private func resolveStandalonePythonExecutable() -> String? {
        let fm = FileManager.default
        let venvPython = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Gemma AI Gallery/litert-lm-venv/bin/python3").path
        var candidates: [String] = [
            venvPython,
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3",
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3",
        ]
        if let info = Bundle.main.infoDictionary,
           let configured = info["EduVisPythonExecutable"] as? String {
            candidates.append(configured)
        }
        candidates.append(contentsOf: [
            "/Library/Developer/CommandLineTools/usr/bin/python3",
            "/usr/bin/python3",
        ])
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private func startStandaloneBackend() -> Bool {
        guard let projectURL = resolveStandaloneProjectURL(),
              let pythonExecutable = resolveStandalonePythonExecutable() else {
            NSLog("Konfigurasi backend mandiri tidak ditemukan.")
            return false
        }
        let scriptURL = projectURL.appendingPathComponent("gemma_chat_gui.py")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            NSLog("Skrip backend tidak ditemukan: %@", scriptURL.path)
            return false
        }

        let defaultReadinessURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EduVis AI Gallery/ready")
        let readinessURL: URL
        if let info = Bundle.main.infoDictionary,
           let configuredPath = info["EduVisReadinessPath"] as? String,
           configuredPath.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) {
            readinessURL = URL(fileURLWithPath: configuredPath)
        } else {
            readinessURL = defaultReadinessURL
        }
        let appSupportDir = readinessURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: appSupportDir,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: readinessURL)
            let logURL = appSupportDir.appendingPathComponent("backend.log")
            try? FileManager.default.removeItem(at: logURL)
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            backendLogHandle = try FileHandle(forWritingTo: logURL)
            baseURL = URL(string: "http://127.0.0.1:1236/utama.html")
            bannerPath = projectURL.appendingPathComponent("Banner.jpg").path
            self.readinessPath = readinessURL.path
        } catch {
            NSLog("Tidak dapat menyiapkan backend mandiri: %@", error.localizedDescription)
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonExecutable)
        process.arguments = [
            scriptURL.path,
            "--backend-only",
            "--readiness",
            readinessURL.path,
        ]
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/Library/Frameworks/Python.framework/Versions/3.14/bin",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin",
            "/Library/Frameworks/Python.framework/Versions/Current/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + (existingPath.isEmpty ? [] : [existingPath])).joined(separator: ":")
        process.environment = env
        if FileManager.default.isWritableFile(atPath: projectURL.path) {
            process.currentDirectoryURL = projectURL
        } else {
            process.currentDirectoryURL = appSupportDir
        }
        process.standardOutput = backendLogHandle
        process.standardError = backendLogHandle
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.standaloneMode else { return }
                self.startupStatus.stringValue = "Backend berhenti (kode \(process.terminationStatus)). Buka ulang aplikasi."
                self.startupStatus.textColor = .systemRed
                self.launchButton.isEnabled = false
            }
        }
        do {
            try process.run()
            backendProcess = process
            standaloneMode = true
            return true
        } catch {
            NSLog("Tidak dapat meluncurkan backend Python: %@", error.localizedDescription)
            return false
        }
    }

    private func makeLiquidGlassSurface(
        cornerRadius: CGFloat,
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        borderAlpha: CGFloat = 0.20,
        tintColor: NSColor? = nil,
        borderColorOverride: NSColor? = nil
    ) -> NSVisualEffectView {
        return LiquidGlassSurfaceView(
            cornerRadius: cornerRadius,
            material: material,
            blendingMode: blendingMode,
            borderAlpha: borderAlpha,
            tintColor: tintColor,
            borderColorOverride: borderColorOverride
        )
    }

    private func makeCleanMyMacRailIcon(
        symbol: String,
        tooltip: String,
        isActive: Bool,
        action: Selector
    ) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 12
        if #available(macOS 10.15, *) {
            wrapper.layer?.cornerCurve = .continuous
        }
        if isActive {
            wrapper.layer?.backgroundColor = NSColor(calibratedRed: 0.30, green: 0.27, blue: 0.48, alpha: 0.82).cgColor
            wrapper.layer?.borderWidth = 1
            wrapper.layer?.borderColor = NSColor(calibratedRed: 0.67, green: 0.62, blue: 0.91, alpha: 0.42).cgColor
        } else {
            wrapper.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
            wrapper.layer?.borderWidth = 0.5
            wrapper.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        }

        let iconImage = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let btn = NSButton(title: "", target: self, action: action)
        btn.image = iconImage
        btn.imagePosition = .imageOnly
        btn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.isBordered = false
        btn.setButtonType(.momentaryChange)
        btn.contentTintColor = isActive
            ? NSColor.white
            : NSColor(calibratedRed: 0.82, green: 0.77, blue: 0.96, alpha: 0.90)
        btn.toolTip = tooltip
        btn.setAccessibilityLabel(tooltip)
        btn.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(btn)

        // Pin penuh NSButton ke wrapper agar SELURUH kotak 44×44pt merespons klik!
        var constraints: [NSLayoutConstraint] = [
            wrapper.widthAnchor.constraint(equalToConstant: 44),
            wrapper.heightAnchor.constraint(equalToConstant: 44),
            btn.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            btn.topAnchor.constraint(equalTo: wrapper.topAnchor),
            btn.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ]

        if isActive {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3.5
            dot.layer?.backgroundColor = NSColor.white.cgColor
            dot.layer?.shadowColor = NSColor(calibratedRed: 0.93, green: 0.28, blue: 0.60, alpha: 1).cgColor
            dot.layer?.shadowRadius = 4
            dot.layer?.shadowOpacity = 0.95
            dot.layer?.shadowOffset = .zero
            dot.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(dot)
            constraints.append(contentsOf: [
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7),
                dot.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
                dot.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -4),
            ])
        }

        NSLayoutConstraint.activate(constraints)
        return wrapper
    }

    private func makeDarkGlassPillButton(
        title: String,
        action: Selector,
        fontSize: CGFloat = 11.5,
        height: CGFloat = 30
    ) -> NSButton {
        return InteractiveDarkGlassPillButton(
            title: title,
            target: self,
            action: action,
            fontSize: fontSize,
            height: height
        )
    }

    private func makeCleanMyMacWorkspaceRow(
        title: String,
        tagText: String,
        symbol: String,
        index: Int,
        isSelected: Bool
    ) -> NSButton {
        return WorkspaceRowButton(
            title: title,
            tagText: tagText,
            symbol: symbol,
            index: index,
            isSelected: isSelected,
            target: self,
            action: #selector(workspaceRowClicked(_:))
        )
    }

    @objc private func workspaceRowClicked(_ sender: NSButton) {
        let index = min(max(sender.tag, 0), appViews.count - 1)
        viewPicker.selectItem(at: index)
        updateLauncherSelectionUI()
    }

    @objc private func launcherPickerChanged(_ sender: NSPopUpButton) {
        updateLauncherSelectionUI()
    }

    private func updateLauncherSelectionUI() {
        let selectedIdx = max(0, viewPicker.indexOfSelectedItem)
        let activeAppView = appViews[min(selectedIdx, appViews.count - 1)]
        launcherSelectedSummary?.stringValue = "Studio Aktif: \(activeAppView.title)"
        launcherFileBadge?.stringValue = " \(activeAppView.path) "
        for btn in workspaceRowButtons {
            let isSel = (btn.tag == selectedIdx)
            if let rowBtn = btn as? WorkspaceRowButton {
                rowBtn.isCurrentSelected = isSel
            } else {
                btn.layer?.backgroundColor = (isSel
                    ? NSColor(calibratedRed: 0.30, green: 0.27, blue: 0.48, alpha: 0.88)
                    : NSColor.white.withAlphaComponent(0.025)
                ).cgColor
                btn.layer?.borderWidth = isSel ? 1 : 0.5
                btn.layer?.borderColor = (isSel
                    ? NSColor(calibratedRed: 0.67, green: 0.62, blue: 0.91, alpha: 0.48)
                    : NSColor.white.withAlphaComponent(0.065)
                ).cgColor
            }
        }
    }

    @objc private func selectLauncherOverview() {
        viewPicker.selectItem(at: 0)
        updateLauncherSelectionUI()
        startupStatus.stringValue = "Space Lens siap · memilih \(appViews[0].title)"
    }

    @objc private func openVisionWorkspace() {
        if let idx = appViews.firstIndex(where: { $0.path == "vision_ulti.html" }) {
            viewPicker.selectItem(at: idx)
            updateLauncherSelectionUI()
            if launchButton.isEnabled {
                openSelectedView()
            }
        }
    }

    private func makeCleanMyMacStorageCard() -> NSView {
        let card = makeLiquidGlassSurface(
            cornerRadius: 14,
            material: .hudWindow,
            blendingMode: .withinWindow,
            borderAlpha: 0.14,
            tintColor: NSColor(calibratedRed: 0.118, green: 0.082, blue: 0.220, alpha: 0.94), // #1E1538
            borderColorOverride: NSColor.white.withAlphaComponent(0.09)
        )

        let totalGB = Int(getPhysicalMemoryGB().rounded())
        let leftTitle = NSTextField(labelWithString: "Apple Silicon Unified")
        leftTitle.font = .systemFont(ofSize: 11.5, weight: .semibold)
        leftTitle.textColor = .white

        let rightStats = NSTextField(labelWithString: "\(totalGB) GB RAM · LiteRT-LM Ready")
        rightStats.font = .systemFont(ofSize: 10.5, weight: .medium)
        rightStats.textColor = NSColor(calibratedRed: 0.80, green: 0.76, blue: 0.95, alpha: 0.92)

        let topRow = NSView()
        topRow.addSubview(leftTitle)
        topRow.addSubview(rightStats)
        leftTitle.translatesAutoresizingMaskIntoConstraints = false
        rightStats.translatesAutoresizingMaskIntoConstraints = false

        let track = NSView()
        track.wantsLayer = true
        track.layer?.cornerRadius = 2.5
        track.layer?.masksToBounds = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        track.translatesAutoresizingMaskIntoConstraints = false

        let whiteSeg = NSView()
        whiteSeg.wantsLayer = true
        whiteSeg.layer?.cornerRadius = 2.5
        whiteSeg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        whiteSeg.translatesAutoresizingMaskIntoConstraints = false

        let pinkSeg = NSView()
        pinkSeg.wantsLayer = true
        pinkSeg.layer?.backgroundColor = NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 1).cgColor
        pinkSeg.translatesAutoresizingMaskIntoConstraints = false

        let purpleSeg = NSView()
        purpleSeg.wantsLayer = true
        purpleSeg.layer?.cornerRadius = 2.5
        purpleSeg.layer?.backgroundColor = NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.98, alpha: 1).cgColor
        purpleSeg.translatesAutoresizingMaskIntoConstraints = false

        track.addSubview(purpleSeg)
        track.addSubview(pinkSeg)
        track.addSubview(whiteSeg)

        let stack = NSStackView(views: [topRow, track])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 48),
            topRow.heightAnchor.constraint(equalToConstant: 15),
            leftTitle.leadingAnchor.constraint(equalTo: topRow.leadingAnchor),
            leftTitle.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            rightStats.trailingAnchor.constraint(equalTo: topRow.trailingAnchor),
            rightStats.centerYAnchor.constraint(equalTo: topRow.centerYAnchor),
            track.heightAnchor.constraint(equalToConstant: 5),
            whiteSeg.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            whiteSeg.topAnchor.constraint(equalTo: track.topAnchor),
            whiteSeg.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            whiteSeg.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.56),
            pinkSeg.leadingAnchor.constraint(equalTo: whiteSeg.trailingAnchor),
            pinkSeg.topAnchor.constraint(equalTo: track.topAnchor),
            pinkSeg.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            pinkSeg.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.16),
            purpleSeg.leadingAnchor.constraint(equalTo: pinkSeg.trailingAnchor),
            purpleSeg.topAnchor.constraint(equalTo: track.topAnchor),
            purpleSeg.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            purpleSeg.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: 0.09),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    private func makeSpaceLensBubble(
        title: String,
        subtitle: String,
        symbol: String,
        diameter: CGFloat,
        isHighlighted: Bool,
        tag: Int,
        accentColor: NSColor? = nil
    ) -> NSView {
        let accent = accentColor ?? (isHighlighted
            ? NSColor(calibratedRed: 0.957, green: 0.247, blue: 0.557, alpha: 1.0)
            : NSColor(calibratedRed: 0.506, green: 0.549, blue: 0.973, alpha: 1.0)
        )
        let bubble = SpaceLensBubbleButton(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            diameter: diameter,
            isHighlighted: isHighlighted,
            tag: tag,
            accentColor: accent,
            target: self,
            action: #selector(spaceLensBubbleClicked(_:))
        )
        bubble.startFloatingAnimation(phase: Double(tag % 7))
        return bubble
    }

    @objc private func spaceLensBubbleClicked(_ sender: NSButton) {
        let index = min(max(sender.tag, 0), appViews.count - 1)
        viewPicker.selectItem(at: index)
        updateLauncherSelectionUI()
        if launchButton.isEnabled {
            openSelectedView()
        }
    }

    private func makeLauncherView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        // Latar belakang Cosmic Violet gelap khas CleanMyMac X
        let background = CAGradientLayer()
        background.colors = [
            NSColor(calibratedRed: 0.055, green: 0.024, blue: 0.137, alpha: 1).cgColor, // #0E0623
            NSColor(calibratedRed: 0.098, green: 0.047, blue: 0.235, alpha: 1).cgColor, // #190C3C
            NSColor(calibratedRed: 0.047, green: 0.020, blue: 0.118, alpha: 1).cgColor, // #0C051E
        ]
        background.startPoint = CGPoint(x: 0.0, y: 1.0)
        background.endPoint = CGPoint(x: 1.0, y: 0.0)
        view.layer?.addSublayer(background)
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.024, blue: 0.137, alpha: 1).cgColor
        view.appearance = NSAppearance(named: .darkAqua)

        let ambientGlass = NSVisualEffectView()
        ambientGlass.material = .underWindowBackground
        ambientGlass.blendingMode = .withinWindow
        ambientGlass.state = .active
        ambientGlass.alphaValue = 0.14
        ambientGlass.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ambientGlass)

        // Header Atas CleanMyMac: Brand + Judul Space Lens (sejajar tengah kanvas kanan) + Status Koneksi
        let brandMark = NSImageView()
        brandMark.imageScaling = .scaleProportionallyUpOrDown
        brandMark.image = NSApp.applicationIconImage
        brandMark.wantsLayer = true
        brandMark.layer?.cornerRadius = 9
        if #available(macOS 10.15, *) {
            brandMark.layer?.cornerCurve = .continuous
        }
        brandMark.layer?.masksToBounds = true
        brandMark.widthAnchor.constraint(equalToConstant: 28).isActive = true
        brandMark.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let brand = NSTextField(labelWithString: "EduVis AI Gallery")
        brand.font = .systemFont(ofSize: 13.5, weight: .bold)
        brand.textColor = .white

        let brandRow = NSStackView(views: [brandMark, brand])
        brandRow.orientation = .horizontal
        brandRow.alignment = .centerY
        brandRow.spacing = 10

        let stageHeaderTitle = NSTextField(labelWithString: "Space Lens  ·  CleanMyMac Studio")
        stageHeaderTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
        stageHeaderTitle.textColor = NSColor(calibratedRed: 0.94, green: 0.90, blue: 1.0, alpha: 0.95)

        let connectionDot = NSTextField(labelWithString: "●")
        connectionDot.font = .systemFont(ofSize: 9, weight: .bold)
        connectionDot.textColor = NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 1)
        let connectionLabel = NSTextField(labelWithString: "Berjalan di jaringan lokal")
        connectionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        connectionLabel.textColor = NSColor(calibratedRed: 0.94, green: 0.90, blue: 1.0, alpha: 0.95)
        let connectionStack = NSStackView(views: [connectionDot, connectionLabel])
        connectionStack.orientation = .horizontal
        connectionStack.alignment = .centerY
        connectionStack.spacing = 6
        connectionStack.edgeInsets = NSEdgeInsets(top: 0, left: 11, bottom: 0, right: 11)
        connectionStack.translatesAutoresizingMaskIntoConstraints = false

        let connection = makeLiquidGlassSurface(
            cornerRadius: 14,
            material: .popover,
            blendingMode: .withinWindow,
            borderAlpha: 0.24,
            tintColor: NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.31, alpha: 0.86),
            borderColorOverride: NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 0.42)
        )
        connection.addSubview(connectionStack)

        let topBar = makeLiquidGlassSurface(
            cornerRadius: 15,
            material: .headerView,
            blendingMode: .withinWindow,
            borderAlpha: 0.14,
            tintColor: NSColor(calibratedRed: 0.118, green: 0.082, blue: 0.220, alpha: 0.92), // #1E1538
            borderColorOverride: NSColor.white.withAlphaComponent(0.08)
        )
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(brandRow)
        topBar.addSubview(stageHeaderTitle)
        topBar.addSubview(connection)
        brandRow.translatesAutoresizingMaskIntoConstraints = false
        stageHeaderTitle.translatesAutoresizingMaskIntoConstraints = false
        connection.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        // Kolom 1: Left Icon Rail ala CleanMyMac X (seluruh tombol area penuh 44×44pt & aktif langsung)
        let railItems: [NSView] = [
            makeCleanMyMacRailIcon(symbol: "square.grid.2x2.fill", tooltip: "Space Lens Overview", isActive: true, action: #selector(selectLauncherOverview)),
            makeCleanMyMacRailIcon(symbol: "play.fill", tooltip: "Buka Ruang Kerja Terpilih", isActive: false, action: #selector(openSelectedView)),
            makeCleanMyMacRailIcon(symbol: "cube.box.fill", tooltip: "Pusat Model LiteRT-LM (.litertlm)", isActive: false, action: #selector(openModelCenter)),
            makeCleanMyMacRailIcon(symbol: "bolt.fill", tooltip: "Tanya Cepat AI / Spotlight (⌘K)", isActive: false, action: #selector(openQuickAskPanel)),
            makeCleanMyMacRailIcon(symbol: "qrcode", tooltip: "Akses LAN HTTPS & QR Code", isActive: false, action: #selector(openNativeLanQRPanel)),
            makeCleanMyMacRailIcon(symbol: "doc.text.magnifyingglass", tooltip: "Buka Vision Ulti (PDF & OCR)", isActive: false, action: #selector(openVisionWorkspace)),
            makeCleanMyMacRailIcon(symbol: "memorychip", tooltip: "Segarkan Memori LiteRT-LM", isActive: false, action: #selector(menuRefreshModelMemory)),
            makeCleanMyMacRailIcon(symbol: "info.circle.fill", tooltip: "Tentang Aplikasi & Developer", isActive: false, action: #selector(openAboutPanel)),
        ]
        let railStack = NSStackView(views: railItems)
        railStack.orientation = .vertical
        railStack.alignment = .centerX
        railStack.spacing = 10
        railStack.translatesAutoresizingMaskIntoConstraints = false

        let leftRail = makeLiquidGlassSurface(
            cornerRadius: 16,
            material: .sidebar,
            blendingMode: .withinWindow,
            borderAlpha: 0.12,
            tintColor: NSColor(calibratedRed: 0.118, green: 0.082, blue: 0.220, alpha: 0.92), // #1E1538
            borderColorOverride: NSColor.white.withAlphaComponent(0.08)
        )
        leftRail.translatesAutoresizingMaskIntoConstraints = false
        leftRail.addSubview(railStack)
        view.addSubview(leftRail)

        // Kolom 2: Master Card Kiri-Tengah (Unified Memory Card 48pt + Scrollable List 13 Workspace + Footer rapi)
        let storageCard = makeCleanMyMacStorageCard()

        let folderIcon = NSImageView()
        folderIcon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Workspace Studio")
        folderIcon.contentTintColor = NSColor(calibratedRed: 0.34, green: 0.80, blue: 0.98, alpha: 1.0)
        folderIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        folderIcon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Pilih ruang kerja Anda.")
        title.font = .systemFont(ofSize: 19, weight: .bold)
        title.textColor = .white

        let subtitle = NSTextField(
            wrappingLabelWithString: "\(appViews.count) antarmuka AI lokal · 100% berjalan di perangkat."
        )
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = NSColor(calibratedRed: 0.82, green: 0.77, blue: 0.95, alpha: 0.88)

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let directoryHeader = NSStackView(views: [folderIcon, titleStack])
        directoryHeader.orientation = .horizontal
        directoryHeader.alignment = .centerY
        directoryHeader.spacing = 12

        let workspaceTitle = NSTextField(labelWithString: "Workspace tersedia")
        workspaceTitle.font = .systemFont(ofSize: 11.5, weight: .semibold)
        workspaceTitle.textColor = .white
        let workspaceCount = NSTextField(labelWithString: "\(appViews.count) tampilan")
        workspaceCount.font = .systemFont(ofSize: 11, weight: .semibold)
        workspaceCount.textColor = NSColor(calibratedRed: 0.95, green: 0.50, blue: 0.78, alpha: 1)
        let workspaceHeader = NSView()
        workspaceHeader.addSubview(workspaceTitle)
        workspaceHeader.addSubview(workspaceCount)
        workspaceTitle.translatesAutoresizingMaskIntoConstraints = false
        workspaceCount.translatesAutoresizingMaskIntoConstraints = false

        // Simpan viewPicker tersembunyi untuk kompatibilitas pemilihan terprogram & pintasan
        viewPicker = NSPopUpButton()
        viewPicker.controlSize = .regular
        viewPicker.addItems(withTitles: appViews.map(\.title))
        viewPicker.target = self
        viewPicker.action = #selector(launcherPickerChanged(_:))
        viewPicker.isHidden = true

        let workspaceMeta: [String: (symbol: String, tag: String)] = [
            "utama.html": ("bubble.left.and.bubble.right.fill", "Studio Chat"),
            "utamaV2.html": ("sparkles.rectangle.stack.fill", "V2 Studio"),
            "VS.html": ("rectangle.split.2x1.fill", "Split View"),
            "claude.html": ("sidebar.right", "Artifacts"),
            "eduVis.html": ("graduationcap.fill", "Sains STEM"),
            "gemini_live.html": ("waveform.circle.fill", "Suara Live"),
            "liquid_chatbot.html": ("drop.fill", "Liquid UI"),
            "aurora.html": ("moon.stars.fill", "Aurora"),
            "tanya-ai-standalone.html": ("questionmark.bubble.fill", "Tanya Cepat"),
            "vision_ulti.html": ("doc.text.magnifyingglass", "PDF & OCR"),
            "analisis-kode.html": ("chevron.left.forwardslash.chevron.right", "Kode"),
            "agen-ai-otonom.html": ("cpu.fill", "Otonom"),
            "mesin-pglite-rag.html": ("cylinder.split.1x2.fill", "Vektor DB"),
        ]

        var createdRowBtns: [NSButton] = []
        for (idx, item) in appViews.enumerated() {
            let meta = workspaceMeta[item.path] ?? ("app.fill", "Studio")
            createdRowBtns.append(makeCleanMyMacWorkspaceRow(
                title: item.title,
                tagText: meta.tag,
                symbol: meta.symbol,
                index: idx,
                isSelected: idx == 0
            ))
        }
        self.workspaceRowButtons = createdRowBtns

        let quickListStack = NSStackView(views: createdRowBtns)
        quickListStack.orientation = .vertical
        quickListStack.alignment = .width
        quickListStack.spacing = 4
        quickListStack.translatesAutoresizingMaskIntoConstraints = false

        let listDocView = FlippedListDocumentView()
        listDocView.translatesAutoresizingMaskIntoConstraints = false
        listDocView.addSubview(quickListStack)

        let workspaceScrollView = NSScrollView()
        workspaceScrollView.hasVerticalScroller = true
        workspaceScrollView.hasHorizontalScroller = false
        workspaceScrollView.autohidesScrollers = true
        workspaceScrollView.scrollerStyle = .overlay
        workspaceScrollView.drawsBackground = false
        workspaceScrollView.borderType = .noBorder
        workspaceScrollView.documentView = listDocView
        workspaceScrollView.translatesAutoresizingMaskIntoConstraints = false

        let workspaceScrollContainer = NSView()
        workspaceScrollContainer.wantsLayer = true
        workspaceScrollContainer.layer?.cornerRadius = 12
        if #available(macOS 10.15, *) {
            workspaceScrollContainer.layer?.cornerCurve = .continuous
        }
        workspaceScrollContainer.layer?.backgroundColor = NSColor(calibratedRed: 0.082, green: 0.055, blue: 0.165, alpha: 0.94).cgColor // #150E2A
        workspaceScrollContainer.layer?.borderWidth = 1
        workspaceScrollContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        workspaceScrollContainer.translatesAutoresizingMaskIntoConstraints = false
        workspaceScrollContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        workspaceScrollContainer.addSubview(workspaceScrollView)

        let sidebarDivider = NSView()
        sidebarDivider.wantsLayer = true
        sidebarDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        sidebarDivider.translatesAutoresizingMaskIntoConstraints = false

        let technologyHeading = NSTextField(labelWithString: "TENTANG TEKNOLOGI")
        technologyHeading.font = .systemFont(ofSize: 9.5, weight: .bold)
        technologyHeading.textColor = NSColor(calibratedRed: 0.65, green: 0.82, blue: 1, alpha: 0.95)
        let liteRTDescription = NSTextField(
            wrappingLabelWithString: "LiteRT-LM lokal dengan Metal GPU & SQLiteVectorStore RAG terpusat."
        )
        liteRTDescription.font = .systemFont(ofSize: 11)
        liteRTDescription.textColor = NSColor(calibratedRed: 0.80, green: 0.76, blue: 0.95, alpha: 0.85)
        let technology = NSStackView(views: [technologyHeading, liteRTDescription])
        technology.orientation = .vertical
        technology.alignment = .leading
        technology.spacing = 3

        let modelCenterButton = makeDarkGlassPillButton(title: "Pusat Model…", action: #selector(openModelCenter))
        let aboutLauncherButton = makeDarkGlassPillButton(title: "Tentang & Developer…", action: #selector(openAboutPanel))

        let launcherActionRow = NSStackView(views: [modelCenterButton, aboutLauncherButton])
        launcherActionRow.orientation = .horizontal
        launcherActionRow.distribution = .fillEqually
        launcherActionRow.spacing = 8

        startupStatus = NSTextField(labelWithString: "Menyiapkan model lokal…")
        startupStatus.font = .systemFont(ofSize: 10.5, weight: .medium)
        startupStatus.textColor = NSColor(calibratedRed: 0.86, green: 0.82, blue: 0.97, alpha: 0.88)

        let modelPillBadge = NSTextField(labelWithString: " memecah model… ")
        modelPillBadge.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        modelPillBadge.textColor = NSColor(calibratedRed: 0.89, green: 0.84, blue: 1.0, alpha: 0.95)
        modelPillBadge.wantsLayer = true
        modelPillBadge.layer?.cornerRadius = 6
        modelPillBadge.layer?.backgroundColor = NSColor(calibratedRed: 0.082, green: 0.055, blue: 0.165, alpha: 0.96).cgColor
        modelPillBadge.layer?.borderWidth = 1
        modelPillBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        modelPillBadge.isHidden = true
        self.launcherModelPillBadge = modelPillBadge

        let startupStatusRow = NSStackView(views: [startupStatus, modelPillBadge])
        startupStatusRow.orientation = .horizontal
        startupStatusRow.alignment = .centerY
        startupStatusRow.spacing = 6

        for section in [directoryHeader, workspaceHeader, sidebarDivider, technology, launcherActionRow, startupStatusRow] as [NSView] {
            section.setContentHuggingPriority(.required, for: .vertical)
            section.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        let controlStack = NSStackView(views: [
            directoryHeader,
            workspaceHeader,
            viewPicker,
            workspaceScrollContainer,
            sidebarDivider,
            technology,
            launcherActionRow,
            startupStatusRow,
        ])
        controlStack.orientation = .vertical
        controlStack.alignment = .leading
        controlStack.spacing = 9
        controlStack.translatesAutoresizingMaskIntoConstraints = false

        let masterListCard = makeLiquidGlassSurface(
            cornerRadius: 18,
            material: .hudWindow,
            blendingMode: .withinWindow,
            borderAlpha: 0.14,
            tintColor: NSColor(calibratedRed: 0.118, green: 0.082, blue: 0.220, alpha: 0.94), // #1E1538
            borderColorOverride: NSColor.white.withAlphaComponent(0.08)
        )
        masterListCard.addSubview(controlStack)

        let leftCenterColumn = NSStackView(views: [storageCard, masterListCard])
        leftCenterColumn.orientation = .vertical
        leftCenterColumn.alignment = .width
        leftCenterColumn.spacing = 12
        leftCenterColumn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftCenterColumn)

        // Kolom 3: Panggung Kanan CleanMyMac "Space Lens" (#130D24 lebih pekat agar kontras dengan sidebar)
        let spaceLensContainer = makeLiquidGlassSurface(
            cornerRadius: 18,
            material: .hudWindow,
            blendingMode: .withinWindow,
            borderAlpha: 0.14,
            tintColor: NSColor(calibratedRed: 0.075, green: 0.051, blue: 0.141, alpha: 0.96), // #130D24
            borderColorOverride: NSColor.white.withAlphaComponent(0.08)
        )
        spaceLensContainer.translatesAutoresizingMaskIntoConstraints = false

        let stageHeaderBar = NSView()
        stageHeaderBar.translatesAutoresizingMaskIntoConstraints = false

        let stageHeaderDivider = NSView()
        stageHeaderDivider.wantsLayer = true
        stageHeaderDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        stageHeaderDivider.translatesAutoresizingMaskIntoConstraints = false

        let lensPathLabel = NSTextField(labelWithString: "🖥  macOS  ›  LiteRT-LM v0.19  ›  \(appViews.count) Ruang Kerja Interaktif")
        lensPathLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        lensPathLabel.textColor = NSColor(calibratedRed: 0.90, green: 0.85, blue: 0.99, alpha: 0.92)
        lensPathLabel.translatesAutoresizingMaskIntoConstraints = false

        let quickAskPill = makeDarkGlassPillButton(title: "⚡ Quick Ask (⌘K)", action: #selector(openQuickAskPanel), fontSize: 11, height: 26)
        quickAskPill.contentTintColor = .white
        let qrPill = makeDarkGlassPillButton(title: "📱 QR LAN", action: #selector(openNativeLanQRPanel), fontSize: 11, height: 26)
        let stageTopPills = NSStackView(views: [quickAskPill, qrPill])
        stageTopPills.orientation = .horizontal
        stageTopPills.spacing = 7
        stageTopPills.translatesAutoresizingMaskIntoConstraints = false

        stageHeaderBar.addSubview(lensPathLabel)
        stageHeaderBar.addSubview(stageTopPills)
        stageHeaderBar.addSubview(stageHeaderDivider)
        spaceLensContainer.addSubview(stageHeaderBar)

        // Klaster Gelembung Space Lens Diperbesar (~25% Utama, ~20% Satelit) + Cincin Orbit & Radial Glow
        let lensCluster = NSView()
        lensCluster.translatesAutoresizingMaskIntoConstraints = false
        spaceLensContainer.addSubview(lensCluster)

        let orbitBackdrop = SpaceLensOrbitBackdropView()
        orbitBackdrop.translatesAutoresizingMaskIntoConstraints = false
        lensCluster.addSubview(orbitBackdrop)

        let bubbleUtama = makeSpaceLensBubble(
            title: "Utama",
            subtitle: "Studio Chat",
            symbol: "bubble.left.and.bubble.right.fill",
            diameter: 146,
            isHighlighted: true,
            tag: 0,
            accentColor: NSColor(calibratedRed: 0.957, green: 0.247, blue: 0.557, alpha: 1.0) // Neon Magenta
        )
        let bubbleEduVis = makeSpaceLensBubble(
            title: "EduVis",
            subtitle: "Sains STEM",
            symbol: "graduationcap.fill",
            diameter: 106,
            isHighlighted: false,
            tag: 4,
            accentColor: NSColor(calibratedRed: 0.133, green: 0.827, blue: 0.933, alpha: 1.0) // Cyan #22D3EE
        )
        let bubbleVision = makeSpaceLensBubble(
            title: "Vision Ulti",
            subtitle: "PDF & OCR",
            symbol: "doc.text.magnifyingglass",
            diameter: 106,
            isHighlighted: false,
            tag: 9,
            accentColor: NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 1.0) // Hot Pink #EC4899
        )
        let bubbleClaude = makeSpaceLensBubble(
            title: "Claude",
            subtitle: "Artifacts",
            symbol: "sidebar.right",
            diameter: 106,
            isHighlighted: false,
            tag: 3,
            accentColor: NSColor(calibratedRed: 0.506, green: 0.549, blue: 0.973, alpha: 1.0) // Indigo #818CF8
        )
        let bubbleRAG = makeSpaceLensBubble(
            title: "PGlite RAG",
            subtitle: "Vektor DB",
            symbol: "cylinder.split.1x2.fill",
            diameter: 106,
            isHighlighted: false,
            tag: 12,
            accentColor: NSColor(calibratedRed: 0.231, green: 0.510, blue: 0.965, alpha: 1.0) // Royal Blue #3B82F6
        )
        let bubbleVoice = makeSpaceLensBubble(
            title: "EduVis Live",
            subtitle: "Suara",
            symbol: "waveform.circle.fill",
            diameter: 106,
            isHighlighted: false,
            tag: 5,
            accentColor: NSColor(calibratedRed: 0.176, green: 0.831, blue: 0.749, alpha: 1.0) // Teal #2DD4BF
        )
        let bubbleAgent = makeSpaceLensBubble(
            title: "Agen AI",
            subtitle: "Otonom",
            symbol: "cpu.fill",
            diameter: 106,
            isHighlighted: false,
            tag: 11,
            accentColor: NSColor(calibratedRed: 0.220, green: 0.741, blue: 0.973, alpha: 1.0) // Sky #38BDF8
        )

        for b in [bubbleUtama, bubbleEduVis, bubbleVision, bubbleClaude, bubbleRAG, bubbleVoice, bubbleAgent] {
            b.translatesAutoresizingMaskIntoConstraints = false
            lensCluster.addSubview(b)
        }

        // Dock Bawah Panggung Kanan ala CleanMyMac Action Bar (Thumbnail 16:9 + Badge Kode File + CTA Gradient)
        let bottomDockCard = makeLiquidGlassSurface(
            cornerRadius: 16,
            material: .popover,
            blendingMode: .withinWindow,
            borderAlpha: 0.14,
            tintColor: NSColor(calibratedRed: 0.118, green: 0.082, blue: 0.220, alpha: 0.92), // #1E1538
            borderColorOverride: NSColor.white.withAlphaComponent(0.09)
        )
        bottomDockCard.translatesAutoresizingMaskIntoConstraints = false

        let banner = InteractivePreviewThumbnailView()
        banner.imageScaling = .scaleProportionallyUpOrDown
        if let bannerPath, let image = NSImage(contentsOfFile: bannerPath) {
            banner.image = image
            banner.setAccessibilityLabel("Banner EduVis AI Gallery")
        } else {
            banner.image = NSImage(named: NSImage.applicationIconName)
        }
        banner.translatesAutoresizingMaskIntoConstraints = false

        let selectedSummary = NSTextField(labelWithString: "Studio Aktif: Utama")
        selectedSummary.font = .systemFont(ofSize: 12.5, weight: .bold)
        selectedSummary.textColor = .white
        self.launcherSelectedSummary = selectedSummary

        let fileBadge = NSTextField(labelWithString: " utama.html ")
        fileBadge.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        fileBadge.textColor = NSColor(calibratedRed: 0.88, green: 0.84, blue: 1.0, alpha: 0.94)
        fileBadge.wantsLayer = true
        fileBadge.layer?.cornerRadius = 6
        fileBadge.layer?.backgroundColor = NSColor(calibratedRed: 0.173, green: 0.125, blue: 0.310, alpha: 0.95).cgColor
        fileBadge.layer?.borderWidth = 1
        fileBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        self.launcherFileBadge = fileBadge

        let summaryTopRow = NSStackView(views: [selectedSummary, fileBadge])
        summaryTopRow.orientation = .horizontal
        summaryTopRow.alignment = .centerY
        summaryTopRow.spacing = 8

        let lensHint = NSTextField(labelWithString: "Siap dijalankan lokal · Klik gelembung Space Lens, pilih di daftar kiri, atau klik Mulai →")
        lensHint.font = .systemFont(ofSize: 10.5)
        lensHint.textColor = NSColor(calibratedRed: 0.80, green: 0.76, blue: 0.95, alpha: 0.85)
        lensHint.lineBreakMode = .byTruncatingTail

        let summaryStack = NSStackView(views: [summaryTopRow, lensHint])
        summaryStack.orientation = .vertical
        summaryStack.alignment = .leading
        summaryStack.spacing = 4

        let gradientLaunch = GradientPillButton(
            title: "Mulai  →",
            target: self,
            action: #selector(openSelectedView)
        )
        launchButton = gradientLaunch
        launchButton.keyEquivalent = "\r"
        launchButton.isEnabled = false
        launchButton.translatesAutoresizingMaskIntoConstraints = false

        bottomDockCard.addSubview(banner)
        bottomDockCard.addSubview(summaryStack)
        bottomDockCard.addSubview(launchButton)
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        spaceLensContainer.addSubview(bottomDockCard)
        view.addSubview(spaceLensContainer)

        NSLayoutConstraint.activate([
            ambientGlass.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ambientGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ambientGlass.topAnchor.constraint(equalTo: view.topAnchor),
            ambientGlass.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            topBar.heightAnchor.constraint(equalToConstant: 48),
            brandRow.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            brandRow.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            // Sejajarkan judul tepat dengan titik tengah area kanvas kanan Space Lens
            stageHeaderTitle.centerXAnchor.constraint(equalTo: spaceLensContainer.centerXAnchor),
            stageHeaderTitle.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            connection.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            connection.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            connection.heightAnchor.constraint(equalToConstant: 28),
            connectionStack.leadingAnchor.constraint(equalTo: connection.leadingAnchor),
            connectionStack.trailingAnchor.constraint(equalTo: connection.trailingAnchor),
            connectionStack.topAnchor.constraint(equalTo: connection.topAnchor),
            connectionStack.bottomAnchor.constraint(equalTo: connection.bottomAnchor),

            leftRail.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            leftRail.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            leftRail.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            leftRail.widthAnchor.constraint(equalToConstant: 64),
            railStack.centerXAnchor.constraint(equalTo: leftRail.centerXAnchor),
            railStack.topAnchor.constraint(equalTo: leftRail.topAnchor, constant: 16),

            leftCenterColumn.leadingAnchor.constraint(equalTo: leftRail.trailingAnchor, constant: 14),
            leftCenterColumn.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            leftCenterColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),
            leftCenterColumn.widthAnchor.constraint(equalToConstant: 360),

            controlStack.leadingAnchor.constraint(equalTo: masterListCard.leadingAnchor, constant: 16),
            controlStack.trailingAnchor.constraint(equalTo: masterListCard.trailingAnchor, constant: -16),
            controlStack.topAnchor.constraint(equalTo: masterListCard.topAnchor, constant: 14),
            controlStack.bottomAnchor.constraint(equalTo: masterListCard.bottomAnchor, constant: -12),
            directoryHeader.widthAnchor.constraint(equalTo: controlStack.widthAnchor),
            workspaceHeader.heightAnchor.constraint(equalToConstant: 18),
            workspaceHeader.widthAnchor.constraint(equalTo: controlStack.widthAnchor),
            workspaceTitle.leadingAnchor.constraint(equalTo: workspaceHeader.leadingAnchor),
            workspaceTitle.centerYAnchor.constraint(equalTo: workspaceHeader.centerYAnchor),
            workspaceCount.trailingAnchor.constraint(equalTo: workspaceHeader.trailingAnchor),
            workspaceCount.centerYAnchor.constraint(equalTo: workspaceHeader.centerYAnchor),
            viewPicker.widthAnchor.constraint(equalTo: controlStack.widthAnchor),
            workspaceScrollContainer.widthAnchor.constraint(equalTo: controlStack.widthAnchor),
            workspaceScrollContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 196),
            workspaceScrollView.leadingAnchor.constraint(equalTo: workspaceScrollContainer.leadingAnchor),
            workspaceScrollView.trailingAnchor.constraint(equalTo: workspaceScrollContainer.trailingAnchor),
            workspaceScrollView.topAnchor.constraint(equalTo: workspaceScrollContainer.topAnchor),
            workspaceScrollView.bottomAnchor.constraint(equalTo: workspaceScrollContainer.bottomAnchor),
            listDocView.leadingAnchor.constraint(equalTo: workspaceScrollView.contentView.leadingAnchor),
            listDocView.trailingAnchor.constraint(equalTo: workspaceScrollView.contentView.trailingAnchor),
            listDocView.topAnchor.constraint(equalTo: workspaceScrollView.contentView.topAnchor),
            listDocView.widthAnchor.constraint(equalTo: workspaceScrollView.contentView.widthAnchor),
            quickListStack.leadingAnchor.constraint(equalTo: listDocView.leadingAnchor, constant: 6),
            quickListStack.trailingAnchor.constraint(equalTo: listDocView.trailingAnchor, constant: -6),
            quickListStack.topAnchor.constraint(equalTo: listDocView.topAnchor, constant: 6),
            quickListStack.bottomAnchor.constraint(equalTo: listDocView.bottomAnchor, constant: -6),
            sidebarDivider.widthAnchor.constraint(equalTo: controlStack.widthAnchor),
            sidebarDivider.heightAnchor.constraint(equalToConstant: 1),
            technology.widthAnchor.constraint(equalTo: controlStack.widthAnchor),
            launcherActionRow.widthAnchor.constraint(equalTo: controlStack.widthAnchor),
            startupStatusRow.widthAnchor.constraint(equalTo: controlStack.widthAnchor),

            spaceLensContainer.leadingAnchor.constraint(equalTo: leftCenterColumn.trailingAnchor, constant: 14),
            spaceLensContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            spaceLensContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            spaceLensContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),

            // Top bar dalam kanvas kanan sama tinggi (48pt) dengan kartu Unified RAM di kiri
            stageHeaderBar.leadingAnchor.constraint(equalTo: spaceLensContainer.leadingAnchor),
            stageHeaderBar.trailingAnchor.constraint(equalTo: spaceLensContainer.trailingAnchor),
            stageHeaderBar.topAnchor.constraint(equalTo: spaceLensContainer.topAnchor),
            stageHeaderBar.heightAnchor.constraint(equalToConstant: 48),
            lensPathLabel.leadingAnchor.constraint(equalTo: stageHeaderBar.leadingAnchor, constant: 18),
            lensPathLabel.centerYAnchor.constraint(equalTo: stageHeaderBar.centerYAnchor),
            stageTopPills.trailingAnchor.constraint(equalTo: stageHeaderBar.trailingAnchor, constant: -16),
            stageTopPills.centerYAnchor.constraint(equalTo: stageHeaderBar.centerYAnchor),
            stageHeaderDivider.leadingAnchor.constraint(equalTo: stageHeaderBar.leadingAnchor),
            stageHeaderDivider.trailingAnchor.constraint(equalTo: stageHeaderBar.trailingAnchor),
            stageHeaderDivider.bottomAnchor.constraint(equalTo: stageHeaderBar.bottomAnchor),
            stageHeaderDivider.heightAnchor.constraint(equalToConstant: 1),

            lensCluster.centerXAnchor.constraint(equalTo: spaceLensContainer.centerXAnchor),
            lensCluster.centerYAnchor.constraint(equalTo: spaceLensContainer.centerYAnchor, constant: -24),
            lensCluster.widthAnchor.constraint(equalToConstant: 476),
            lensCluster.heightAnchor.constraint(equalToConstant: 416),

            orbitBackdrop.leadingAnchor.constraint(equalTo: lensCluster.leadingAnchor),
            orbitBackdrop.trailingAnchor.constraint(equalTo: lensCluster.trailingAnchor),
            orbitBackdrop.topAnchor.constraint(equalTo: lensCluster.topAnchor),
            orbitBackdrop.bottomAnchor.constraint(equalTo: lensCluster.bottomAnchor),

            // Koordinat Heksagonal R = 148pt (Utama 146pt, Satelit 106pt, jarak bebas bertumpuk)
            bubbleUtama.centerXAnchor.constraint(equalTo: lensCluster.centerXAnchor),
            bubbleUtama.centerYAnchor.constraint(equalTo: lensCluster.centerYAnchor),
            bubbleEduVis.centerXAnchor.constraint(equalTo: bubbleUtama.centerXAnchor),
            bubbleEduVis.centerYAnchor.constraint(equalTo: bubbleUtama.centerYAnchor, constant: -148),
            bubbleVision.centerXAnchor.constraint(equalTo: bubbleUtama.centerXAnchor, constant: 128),
            bubbleVision.centerYAnchor.constraint(equalTo: bubbleUtama.centerYAnchor, constant: -74),
            bubbleClaude.centerXAnchor.constraint(equalTo: bubbleUtama.centerXAnchor, constant: 128),
            bubbleClaude.centerYAnchor.constraint(equalTo: bubbleUtama.centerYAnchor, constant: 74),
            bubbleRAG.centerXAnchor.constraint(equalTo: bubbleUtama.centerXAnchor),
            bubbleRAG.centerYAnchor.constraint(equalTo: bubbleUtama.centerYAnchor, constant: 148),
            bubbleVoice.centerXAnchor.constraint(equalTo: bubbleUtama.centerXAnchor, constant: -128),
            bubbleVoice.centerYAnchor.constraint(equalTo: bubbleUtama.centerYAnchor, constant: 74),
            bubbleAgent.centerXAnchor.constraint(equalTo: bubbleUtama.centerXAnchor, constant: -128),
            bubbleAgent.centerYAnchor.constraint(equalTo: bubbleUtama.centerYAnchor, constant: -74),

            bottomDockCard.leadingAnchor.constraint(equalTo: spaceLensContainer.leadingAnchor, constant: 16),
            bottomDockCard.trailingAnchor.constraint(equalTo: spaceLensContainer.trailingAnchor, constant: -16),
            bottomDockCard.bottomAnchor.constraint(equalTo: spaceLensContainer.bottomAnchor, constant: -16),
            bottomDockCard.heightAnchor.constraint(equalToConstant: 86),

            banner.leadingAnchor.constraint(equalTo: bottomDockCard.leadingAnchor, constant: 12),
            banner.centerYAnchor.constraint(equalTo: bottomDockCard.centerYAnchor),
            banner.widthAnchor.constraint(equalToConstant: 114),
            banner.heightAnchor.constraint(equalToConstant: 64),

            summaryStack.leadingAnchor.constraint(equalTo: banner.trailingAnchor, constant: 14),
            summaryStack.centerYAnchor.constraint(equalTo: bottomDockCard.centerYAnchor),
            summaryStack.trailingAnchor.constraint(lessThanOrEqualTo: launchButton.leadingAnchor, constant: -14),

            launchButton.trailingAnchor.constraint(equalTo: bottomDockCard.trailingAnchor, constant: -14),
            launchButton.centerYAnchor.constraint(equalTo: bottomDockCard.centerYAnchor),
            launchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 138),
            launchButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        func allowHorizontalCompression(_ targetView: NSView) {
            targetView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            targetView.subviews.forEach(allowHorizontalCompression)
        }
        allowHorizontalCompression(view)
        for protectedView in [quickAskPill, qrPill, launchButton as NSView] {
            protectedView.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        background.frame = view.bounds
        background.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return view
    }

    private func getPhysicalMemoryGB() -> Double {
        return Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }

    private func checkModelMemoryRequirement(modelName: String) -> String? {
        let systemRAM = getPhysicalMemoryGB()
        let lower = modelName.lowercased()

        if lower.contains("31b") || lower.contains("26b") || lower.contains("27b") {
            if systemRAM < 32.0 {
                return String(format: "⚠️ RAM Disarankan ≥ 32 GB (Sistem: %.0f GB)", systemRAM)
            }
        } else if lower.contains("12b") || lower.contains("14b") {
            if systemRAM < 16.0 {
                return String(format: "⚠️ RAM Disarankan ≥ 16 GB (Sistem: %.0f GB)", systemRAM)
            }
        }
        return nil
    }

    private func updateStartupStatus() {
        let bootstrapURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EduVis AI Gallery/bootstrap_status.json")
        guard let readinessPath,
              FileManager.default.fileExists(atPath: readinessPath) else {
            if let data = try? Data(contentsOf: bootstrapURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String,
               !msg.isEmpty {
                startupStatus.stringValue = msg
            }
            return
        }
        do {
            let modelID = try String(contentsOfFile: readinessPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            selectedModelID = modelID.isEmpty ? nil : modelID
            if let modelID = selectedModelID {
                let pillText = modelID.hasSuffix(".litertlm") ? modelID : "\(modelID).litertlm"
                if let advisory = checkModelMemoryRequirement(modelName: modelID) {
                    startupStatus.stringValue = "Siap digunakan (\(advisory)):"
                } else {
                    startupStatus.stringValue = "Siap digunakan:"
                }
                launcherModelPillBadge?.stringValue = " \(pillText) "
                launcherModelPillBadge?.isHidden = false
            } else {
                startupStatus.stringValue = "Siap digunakan:"
                launcherModelPillBadge?.stringValue = " impor via Pusat Model "
                launcherModelPillBadge?.isHidden = false
            }
            launchButton.isEnabled = true
            readinessTimer?.invalidate()
            readinessTimer = nil
            refreshMemoryStats()
            updateStatusItemModel()
        } catch {
            NSLog("Tidak dapat membaca status kesiapan aplikasi: \(error)")
            startupStatus.stringValue = "Gagal membaca status kesiapan aplikasi."
        }
    }

    @objc private func openModelCenter() {
        if modelPanel == nil {
            makeModelCenter()
        }
        refreshModels()
        modelPanel?.center()
        modelPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadDeveloperPhoto() -> NSImage? {
        if let bundleURL = Bundle.main.url(forResource: "dev", withExtension: "jpeg"),
           let img = NSImage(contentsOf: bundleURL) {
            return img
        }
        var candidatePaths: [String] = []
        if let info = Bundle.main.infoDictionary,
           let projectDir = info["EduVisProjectDirectory"] as? String {
            candidatePaths.append(
                URL(fileURLWithPath: projectDir)
                    .appendingPathComponent("nano_asset/dev.jpeg").path
            )
        }
        if let bannerPath {
            let projectDir = URL(fileURLWithPath: bannerPath).deletingLastPathComponent()
            candidatePaths.append(projectDir.appendingPathComponent("nano_asset/dev.jpeg").path)
        }
        candidatePaths.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("nano_asset/dev.jpeg").path
        )
        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            if let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return nil
    }

    @objc private func openAboutPanel() {
        if aboutPanel == nil {
            makeAboutPanel()
        }
        aboutPanel?.center()
        aboutPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeAboutSectionCard(title: String, body: String) -> NSView {
        let card = makeLiquidGlassSurface(
            cornerRadius: 14,
            material: .contentBackground,
            blendingMode: .withinWindow,
            borderAlpha: 0.16
        )

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 11.5, weight: .bold)
        heading.textColor = .labelColor

        let desc = NSTextField(wrappingLabelWithString: body)
        desc.font = .systemFont(ofSize: 12.5)
        desc.textColor = .secondaryLabelColor
        desc.maximumNumberOfLines = 0

        let stack = NSStackView(views: [heading, desc])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func makeAboutPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 632, height: 630),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Tentang Aplikasi, Cara Kerja & Developer"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false

        let glassBackground = NSVisualEffectView()
        glassBackground.material = .hudWindow
        glassBackground.blendingMode = .behindWindow
        glassBackground.state = .active
        glassBackground.translatesAutoresizingMaskIntoConstraints = false

        // 1. Kartu Profil Developer (Subuh Kurniawan + nano_asset/dev.jpeg)
        let devCard = makeLiquidGlassSurface(
            cornerRadius: 16,
            material: .popover,
            blendingMode: .withinWindow,
            borderAlpha: 0.24
        )
        devCard.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08).cgColor

        let avatarView = NSImageView()
        avatarView.imageScaling = .scaleProportionallyUpOrDown
        avatarView.wantsLayer = true
        avatarView.layer?.cornerRadius = 38
        if #available(macOS 10.15, *) {
            avatarView.layer?.cornerCurve = .continuous
        }
        avatarView.layer?.masksToBounds = true
        avatarView.layer?.borderWidth = 2
        avatarView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.65).cgColor
        avatarView.image = loadDeveloperPhoto() ?? NSApp.applicationIconImage
        avatarView.setAccessibilityLabel("Foto Developer Subuh Kurniawan")
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 76),
            avatarView.heightAnchor.constraint(equalToConstant: 76),
        ])

        let devEyebrow = NSTextField(labelWithString: "DEVELOPER  ·  EDUVIS PROJECT")
        devEyebrow.font = .systemFont(ofSize: 10, weight: .bold)
        devEyebrow.textColor = .systemBlue

        let devName = NSTextField(labelWithString: "Subuh Kurniawan")
        devName.font = .systemFont(ofSize: 18, weight: .bold)
        devName.textColor = .labelColor

        let devBio = NSTextField(
            wrappingLabelWithString: "Membangun pengalaman AI lokal yang praktis untuk pembelajaran, kerja, dan eksplorasi model di perangkat sendiri dengan kedaulatan data penuh."
        )
        devBio.font = .systemFont(ofSize: 12)
        devBio.textColor = .secondaryLabelColor

        let devTags = NSTextField(
            labelWithString: "Local LLM  ·  LiteRT-LM  ·  WebGPU Runtime  ·  Multimodal AI  ·  Vector RAG"
        )
        devTags.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        devTags.textColor = .tertiaryLabelColor

        let devTextStack = NSStackView(views: [devEyebrow, devName, devBio, devTags])
        devTextStack.orientation = .vertical
        devTextStack.alignment = .leading
        devTextStack.spacing = 4

        let devRow = NSStackView(views: [avatarView, devTextStack])
        devRow.orientation = .horizontal
        devRow.alignment = .centerY
        devRow.spacing = 16
        devRow.translatesAutoresizingMaskIntoConstraints = false
        devCard.addSubview(devRow)
        NSLayoutConstraint.activate([
            devRow.leadingAnchor.constraint(equalTo: devCard.leadingAnchor, constant: 16),
            devRow.trailingAnchor.constraint(equalTo: devCard.trailingAnchor, constant: -16),
            devRow.topAnchor.constraint(equalTo: devCard.topAnchor, constant: 14),
            devRow.bottomAnchor.constraint(equalTo: devCard.bottomAnchor, constant: -14),
        ])

        // 2. Tentang Aplikasi
        let aboutAppCard = makeAboutSectionCard(
            title: "TENTANG APLIKASI — EDUVIS AI GALLERY (GEMMA 4 LOCAL SUITE)",
            body: "EduVis AI Gallery adalah platform asisten kecerdasan buatan lokal (100% On-Device & Offline-First) untuk macOS yang menyatukan \(appViews.count) ruang kerja khusus (Utama, Utama V2, VS, Claude, EduVis, EduVis Live, Liquid Chatbot, Aurora, Analisis Kode, Tanya AI, Agen AI Otonom, dan PGlite Vector SQL). Seluruh pemrosesan percakapan, dokumen, gambar, dan basis pengetahuan berjalan mandiri di perangkat Anda dengan privasi penuh."
        )

        // 3. Cara Kerja & Arsitektur Sistem
        let howItWorksCard = makeAboutSectionCard(
            title: "CARA KERJA & ARSITEKTUR SISTEM",
            body: """
            1. Mesin Inferensi Lokal (LiteRT-LM & WebGPU): Menjalankan model .litertlm (seperti Gemma 4 E2B/E4B) secara lokal melalui API kompatibel OpenAI di perangkat host dengan akselerasi Apple Silicon.
            2. Smart API Gateway & RAG Vektor Terpusat (SQLiteVectorStore): Menyimpan dan mencari potongan dokumen lintas ruang kerja menggunakan embedding semantik (multilingual-e5-small) serta memadatkan memori percakapan otomatis (Context Memory Compaction).
            3. Multimodal, Suara & Ekspor Dokumen Native: Mendukung analisis dokumen (PDF, DOCX, XLSX, CSV), gambar/kamera, pengenalan suara native macOS (SFSpeechRecognizer & AVSpeechSynthesizer), serta ekspor instan ke PDF, DOCX (MS Word), PNG, dan SVG.
            """
        )

        // 4. Panduan Cepat Penggunaan
        let guideCard = makeAboutSectionCard(
            title: "PANDUAN CEPAT PENGGUNAAN",
            body: """
            • Langkah 1 — Siapkan Model: Buka “Pusat Model…” atau klik ikon Pengaturan (⌘,) di toolbar untuk memilih atau mengimpor file model .litertlm.
            • Langkah 2 — Pilih Ruang Kerja: Gunakan menu pemilih di kiri atas toolbar (atau pintasan ⌘1–⌘9) untuk berpindah antar ruang kerja secara instan tanpa memutus sesi aktif.
            • Langkah 3 — Knowledge Base & Akses LAN: Unggah dokumen pada panel Knowledge Base untuk tanya-jawab berbasis referensi (RAG), atau klik ikon QR di toolbar kanan atas untuk mengakses dari perangkat lain di jaringan Wi-Fi yang sama.
            """
        )

        let closeBtn = NSButton(title: "Tutup", target: self, action: #selector(closeAboutPanel))
        closeBtn.bezelStyle = .rounded
        closeBtn.controlSize = .large
        closeBtn.keyEquivalent = "\r"

        let stack = NSStackView(views: [devCard, aboutAppCard, howItWorksCard, guideCard, closeBtn])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let contentView = panel.contentView {
            contentView.addSubview(glassBackground)
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                glassBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                glassBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                glassBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
                glassBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            ])
        }
        aboutPanel = panel
    }

    @objc private func closeAboutPanel() {
        aboutPanel?.orderOut(nil)
    }

    private func makeModelCenter() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 656, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pusat Model"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false

        let glassBackground = NSVisualEffectView()
        glassBackground.material = .hudWindow
        glassBackground.blendingMode = .withinWindow
        glassBackground.state = .active
        glassBackground.wantsLayer = true
        glassBackground.layer?.backgroundColor = NSColor(calibratedRed: 0.095, green: 0.042, blue: 0.23, alpha: 0.96).cgColor
        glassBackground.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Model LiteRT-LM")
        heading.font = .systemFont(ofSize: 22, weight: .bold)
        heading.textColor = .white
        let subtitle = NSTextField(wrappingLabelWithString: "Lihat status service, pilih model untuk workspace, atau impor model baru.")
        subtitle.textColor = NSColor(calibratedRed: 0.82, green: 0.77, blue: 0.96, alpha: 0.9)
        subtitle.font = .systemFont(ofSize: 12)

        modelStatus = NSTextField(labelWithString: "Memeriksa service LiteRT-LM…")
        modelStatus.textColor = NSColor(calibratedRed: 0.92, green: 0.88, blue: 1, alpha: 0.88)
        modelStatus.font = .systemFont(ofSize: 12)
        modelPicker = NSPopUpButton()
        modelPicker.controlSize = .large
        modelPicker.addItem(withTitle: "Memuat model…")

        let refreshButton = NSButton(title: "Muat Ulang", target: self, action: #selector(refreshModels))
        refreshButton.bezelStyle = .rounded
        let syncButton = NSButton(title: "Sinkronkan Model Proyek", target: self, action: #selector(syncProjectModels))
        syncButton.bezelStyle = .rounded
        let selectButton = NSButton(title: "Gunakan Model", target: self, action: #selector(selectModel))
        selectButton.bezelStyle = .rounded
        selectButton.bezelColor = NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 1.0)
        selectButton.contentTintColor = .white
        let deleteButton = NSButton(title: "Hapus…", target: self, action: #selector(confirmDeleteModel))
        deleteButton.bezelStyle = .rounded
        let modelActions = NSStackView(views: [refreshButton, syncButton, selectButton, deleteButton])
        modelActions.orientation = .horizontal
        modelActions.alignment = .centerY
        modelActions.spacing = 8

        let activeModelCard = makeLiquidGlassSurface(
            cornerRadius: 16,
            material: .contentBackground,
            blendingMode: .withinWindow,
            borderAlpha: 0.22,
            tintColor: NSColor(calibratedRed: 0.24, green: 0.13, blue: 0.46, alpha: 0.68),
            borderColorOverride: NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 0.30)
        )
        let activeModelStack = NSStackView(views: [modelStatus, modelPicker, modelActions])
        activeModelStack.orientation = .vertical
        activeModelStack.alignment = .width
        activeModelStack.spacing = 10
        activeModelStack.translatesAutoresizingMaskIntoConstraints = false
        activeModelCard.addSubview(activeModelStack)
        NSLayoutConstraint.activate([
            activeModelStack.leadingAnchor.constraint(equalTo: activeModelCard.leadingAnchor, constant: 16),
            activeModelStack.trailingAnchor.constraint(equalTo: activeModelCard.trailingAnchor, constant: -16),
            activeModelStack.topAnchor.constraint(equalTo: activeModelCard.topAnchor, constant: 14),
            activeModelStack.bottomAnchor.constraint(equalTo: activeModelCard.bottomAnchor, constant: -14),
        ])

        let modelIDLabel = NSTextField(labelWithString: "ID model")
        modelIDLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        modelIDField = NSTextField()
        modelIDField.placeholderString = "Contoh: gemma-4-E2B-it"
        modelIDField.toolTip = "Huruf, angka, titik, garis bawah, dan tanda hubung"
        modelImportButton = NSButton(title: "Pilih File Model…", target: self, action: #selector(chooseModelFile))
        modelImportButton.bezelStyle = .rounded
        let downloadCatalogButton = NSButton(
            title: "Unduh Model (.litertlm) Resmi…",
            target: self,
            action: #selector(openModelDownloadCatalog)
        )
        downloadCatalogButton.bezelStyle = .rounded
        let importButtonRow = NSStackView(views: [modelImportButton, downloadCatalogButton])
        importButtonRow.orientation = .horizontal
        importButtonRow.distribution = .fillEqually
        importButtonRow.spacing = 8

        let dropLabel = NSTextField(wrappingLabelWithString: "Seret file .litertlm ke sini untuk mengimpor")
        dropLabel.alignment = .center
        dropLabel.textColor = .secondaryLabelColor
        dropLabel.font = .systemFont(ofSize: 13, weight: .medium)
        modelDropView = ModelDropView(frame: .zero)
        modelDropView.wantsLayer = true
        modelDropView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.42).cgColor
        modelDropView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        modelDropView.layer?.borderWidth = 1
        modelDropView.layer?.cornerRadius = 14
        if #available(macOS 10.15, *) {
            modelDropView.layer?.cornerCurve = .continuous
        }
        modelDropView.addSubview(dropLabel)
        dropLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dropLabel.leadingAnchor.constraint(equalTo: modelDropView.leadingAnchor, constant: 12),
            dropLabel.trailingAnchor.constraint(equalTo: modelDropView.trailingAnchor, constant: -12),
            dropLabel.centerYAnchor.constraint(equalTo: modelDropView.centerYAnchor),
        ])
        modelDropView.onDrop = { [weak self] url in self?.importModel(from: url) }

        let importCard = makeLiquidGlassSurface(
            cornerRadius: 16,
            material: .contentBackground,
            blendingMode: .withinWindow,
            borderAlpha: 0.16
        )
        let importStack = NSStackView(views: [modelIDLabel, modelIDField, importButtonRow, modelDropView])
        importStack.orientation = .vertical
        importStack.alignment = .width
        importStack.spacing = 10
        importStack.translatesAutoresizingMaskIntoConstraints = false
        importCard.addSubview(importStack)
        NSLayoutConstraint.activate([
            importStack.leadingAnchor.constraint(equalTo: importCard.leadingAnchor, constant: 16),
            importStack.trailingAnchor.constraint(equalTo: importCard.trailingAnchor, constant: -16),
            importStack.topAnchor.constraint(equalTo: importCard.topAnchor, constant: 14),
            importStack.bottomAnchor.constraint(equalTo: importCard.bottomAnchor, constant: -14),
            modelDropView.heightAnchor.constraint(equalToConstant: 96),
            importButtonRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])

        let content = NSStackView(views: [
            heading, subtitle, activeModelCard, importCard,
        ])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(glassBackground)
        panel.contentView?.addSubview(content)
        NSLayoutConstraint.activate([
            glassBackground.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            glassBackground.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 22),
            content.bottomAnchor.constraint(lessThanOrEqualTo: panel.contentView!.bottomAnchor, constant: -22),
        ])
        modelPicker.target = self
        modelPicker.action = #selector(modelSelectionChanged)
        modelPanel = panel
    }

    @objc private func openModelDownloadCatalog() {
        if let url = URL(string: "https://huggingface.co/litert-community") {
            NSWorkspace.shared.open(url)
        }
    }

    private func modelAPIURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    @objc private func refreshModels() {
        guard let url = modelAPIURL(path: "/api/models") else {
            modelStatus.stringValue = "URL service model tidak valid."
            return
        }
        modelStatus.stringValue = "Memeriksa service LiteRT-LM…"
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        modelSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil,
                      let response = response as? HTTPURLResponse,
                      let data,
                      response.statusCode == 200 else {
                    let detail = error?.localizedDescription ?? "Respons service tidak valid."
                    self.modelStatus.stringValue = "Service tidak tersedia: \(detail)"
                    self.modelPicker.removeAllItems()
                    self.modelPicker.addItem(withTitle: "Service tidak tersedia")
                    return
                }
                do {
                    guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let models = payload["models"] as? [String] else {
                        throw NSError(domain: "EduVisModelCenter", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "Format daftar model tidak valid."
                        ])
                    }
                    self.modelPicker.removeAllItems()
                    if models.isEmpty {
                        self.modelPicker.addItem(withTitle: "Belum ada model")
                        self.modelStatus.stringValue = "Service aktif · belum ada model terimpor."
                    } else {
                        self.modelPicker.addItems(withTitles: models)
                        if let selected = self.selectedModelID, models.contains(selected) {
                            self.modelPicker.selectItem(withTitle: selected)
                        } else if let first = models.first {
                            self.selectedModelID = first
                        }
                        self.modelStatus.stringValue = "Service aktif · \(models.count) model tersedia."
                        self.fetchModelCapabilitiesSummary(modelCount: models.count)
                    }
                } catch {
                    self.modelStatus.stringValue = "Gagal membaca daftar model: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    @objc private func syncProjectModels() {
        guard let url = modelAPIURL(path: "/api/models/sync-local") else {
            modelStatus.stringValue = "URL sinkronisasi model tidak valid."
            return
        }
        modelStatus.stringValue = "Menyinkronkan model .litertlm proyek…"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        modelSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.modelStatus.stringValue = "Sinkronisasi gagal: \(error.localizedDescription)"
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else {
                    self.modelStatus.stringValue = "Gagal menyinkronkan model proyek."
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let synced = json["synced_models"] as? [String], !synced.isEmpty {
                    self.modelStatus.stringValue = "Disinkronkan \(synced.count) model baru. Memuat ulang…"
                }
                self.refreshModels()
            }
        }.resume()
    }

    private func fetchModelCapabilitiesSummary(modelCount: Int) {
        guard let url = modelAPIURL(path: "/api/models/inspect") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        modelSession.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let version = payload["litert_lm_version"] as? String
            let entries = payload["models"] as? [[String: Any]] ?? []
            var summaries: [String: String] = [:]
            for item in entries {
                guard let id = item["id"] as? String ?? item["filename"] as? String else { continue }
                let rawModalities = (item["modalities"] as? [String]) ?? ["text"]
                var parts = rawModalities.map { $0.capitalized }
                if (item["supports_mtp"] as? Bool) == true {
                    parts.append("MTP")
                }
                if let backend = item["default_backend"] as? String, !backend.isEmpty {
                    parts.append(backend.uppercased())
                }
                summaries[id] = parts.joined(separator: " · ")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.litertRuntimeVersion = version
                self.modelInspectSummaries = summaries
                self.updateModelStatusWithCapabilities(modelCount: modelCount)
            }
        }.resume()
    }

    private func updateModelStatusWithCapabilities(modelCount: Int? = nil) {
        let verPrefix = litertRuntimeVersion.map { "LiteRT-LM v\($0)" } ?? "Service aktif"
        let countPart = modelCount.map { " · \($0) model" } ?? ""
        if let active = selectedModelID, let summary = modelInspectSummaries[active] {
            modelStatus.stringValue = "\(verPrefix)\(countPart) · \(summary)"
        } else if let active = selectedModelID, let fallback = modelInspectSummaries.first(where: { $0.key.hasPrefix(active) || active.hasPrefix($0.key) })?.value {
            modelStatus.stringValue = "\(verPrefix)\(countPart) · \(fallback)"
        }
    }

    @objc private func modelSelectionChanged() {
        guard modelPicker.indexOfSelectedItem >= 0 else { return }
        let title = modelPicker.titleOfSelectedItem ?? ""
        selectedModelID = title == "Belum ada model" || title == "Service tidak tersedia" ? nil : title
        if let modelID = selectedModelID, let advisory = checkModelMemoryRequirement(modelName: modelID) {
            modelStatus.stringValue = advisory
        } else {
            updateModelStatusWithCapabilities()
        }
    }

    @objc private func selectModel() {
        modelSelectionChanged()
        guard let modelID = selectedModelID else {
            modelStatus.stringValue = "Pilih model yang tersedia terlebih dahulu."
            return
        }
        if let advisory = checkModelMemoryRequirement(modelName: modelID) {
            modelStatus.stringValue = "Model dipilih. \(advisory)"
        } else {
            modelStatus.stringValue = "Model dipilih untuk workspace berikutnya."
        }
        updateStatusItemModel()
    }

    @objc private func confirmDeleteModel() {
        modelSelectionChanged()
        guard let modelID = selectedModelID else {
            modelStatus.stringValue = "Pilih model yang akan dihapus."
            return
        }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Hapus model “\(modelID)”?"
        alert.informativeText = "Model akan dihapus permanen dari penyimpanan LiteRT-LM."
        alert.addButton(withTitle: "Hapus")
        alert.addButton(withTitle: "Batal")
        alert.beginSheetModal(for: modelPanel!) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.sendModelDeleteRequest(modelID)
        }
    }

    private func sendModelDeleteRequest(_ modelID: String) {
        guard let url = modelAPIURL(path: "/api/delete-model") else {
            modelStatus.stringValue = "URL service model tidak valid."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model_id": modelID])
        modelStatus.stringValue = "Menghapus model \(modelID)…"
        modelSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.modelStatus.stringValue = "Gagal menghapus model: \(error.localizedDescription)"
                    return
                }
                guard let response = response as? HTTPURLResponse, let data else {
                    self.modelStatus.stringValue = "Service mengembalikan respons penghapusan yang tidak valid."
                    return
                }
                if response.statusCode != 200 {
                    self.modelStatus.stringValue = self.modelErrorMessage(from: data, fallback: "Gagal menghapus model.")
                    return
                }
                if self.selectedModelID == modelID { self.selectedModelID = nil }
                self.modelStatus.stringValue = "Model berhasil dihapus."
                self.refreshModels()
            }
        }.resume()
    }

    @objc private func chooseModelFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Pilih file model LiteRT-LM (.litertlm)"
        panel.beginSheetModal(for: modelPanel!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importModel(from: url)
        }
    }

    private func importModel(from url: URL) {
        guard url.pathExtension.lowercased() == "litertlm" else {
            modelStatus.stringValue = "File harus berformat .litertlm."
            return
        }
        if modelIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modelIDField.stringValue = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: " ", with: "-")
        }
        let modelID = modelIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelID.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil else {
            modelStatus.stringValue = "ID model harus berisi huruf, angka, titik, garis bawah, atau tanda hubung."
            return
        }
        guard let endpoint = modelAPIURL(
            path: "/api/import-model-upload",
            queryItems: [
                URLQueryItem(name: "model_id", value: modelID),
                URLQueryItem(name: "filename", value: url.lastPathComponent),
            ]
        ) else {
            modelStatus.stringValue = "URL unggah model tidak valid."
            return
        }

        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
            modelStatus.stringValue = "File model tidak dapat dibaca."
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        modelImportButton.isEnabled = false
        modelStatus.stringValue = "Mengunggah \(url.lastPathComponent)…"
        modelSession.uploadTask(with: request, fromFile: url) { [weak self] data, response, error in
            if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.modelImportButton.isEnabled = true
                if let error {
                    self.modelStatus.stringValue = "Unggah/impor gagal: \(error.localizedDescription)"
                    return
                }
                guard let response = response as? HTTPURLResponse, let data else {
                    self.modelStatus.stringValue = "Service mengembalikan respons impor yang tidak valid."
                    return
                }
                guard response.statusCode == 200 else {
                    self.modelStatus.stringValue = self.modelErrorMessage(from: data, fallback: "Impor model gagal.")
                    return
                }
                self.selectedModelID = modelID
                self.modelStatus.stringValue = "Model \(modelID) berhasil diimpor dan dipilih."
                self.refreshModels()
            }
        }.resume()
    }

    private func modelErrorMessage(from data: Data, fallback: String) -> String {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = payload["error"] as? String else { return fallback }
        return message
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Int(Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100)
        DispatchQueue.main.async { [weak self] in
            self?.modelStatus.stringValue = "Mengunggah model… \(progress)%"
        }
    }

    private func makeToolbarButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let btn = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(),
            target: self,
            action: action
        )
        btn.bezelStyle = .toolbar
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip = tooltip
        btn.setAccessibilityLabel(tooltip)
        return btn
    }

    private func makeWebContainer() -> NSView {
        let container = NSView()
        navigationBar = NSVisualEffectView()
        navigationBar.material = .headerView
        navigationBar.blendingMode = .withinWindow
        navigationBar.state = .followsWindowActiveState
        navigationBar.wantsLayer = true
        navigationBar.layer?.backgroundColor = NSColor(calibratedRed: 0.095, green: 0.042, blue: 0.23, alpha: 0.92).cgColor

        let backButton = makeToolbarButton(
            symbol: "chevron.left",
            tooltip: "Kembali ke Peluncur Ruang Kerja",
            action: #selector(showLauncher)
        )
        backButton.contentTintColor = NSColor(calibratedRed: 0.96, green: 0.50, blue: 0.78, alpha: 1)
        let sidebarToggle = makeToolbarButton(
            symbol: "sidebar.left",
            tooltip: "Tampilkan/Sembunyikan Sidebar (⌘⌥S)",
            action: #selector(menuToggleSidebar)
        )

        let wsPicker = NSPopUpButton()
        wsPicker.controlSize = .small
        wsPicker.bezelStyle = .texturedRounded
        wsPicker.font = .systemFont(ofSize: 12, weight: .medium)
        wsPicker.addItems(withTitles: appViews.map(\.title))
        wsPicker.target = self
        wsPicker.action = #selector(toolbarWorkspaceChanged(_:))
        wsPicker.toolTip = "Pilih Ruang Kerja"
        self.toolbarWorkspacePicker = wsPicker

        let leftStack = NSStackView(views: [backButton, sidebarToggle, wsPicker])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 6
        leftStack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let leftPill = makeLiquidGlassSurface(
            cornerRadius: 12,
            material: .popover,
            blendingMode: .withinWindow,
            borderAlpha: 0.22,
            tintColor: NSColor(calibratedRed: 0.24, green: 0.12, blue: 0.46, alpha: 0.62),
            borderColorOverride: NSColor(calibratedRed: 0.72, green: 0.45, blue: 0.98, alpha: 0.28)
        )
        leftPill.addSubview(leftStack)
        self.toolbarLeftPill = leftPill

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        webTitle = title

        let modelBadge = NSTextField(labelWithString: "")
        modelBadge.font = .systemFont(ofSize: 11, weight: .regular)
        modelBadge.textColor = NSColor(calibratedRed: 0.95, green: 0.56, blue: 0.80, alpha: 0.95)
        modelBadge.lineBreakMode = .byTruncatingTail
        modelBadge.maximumNumberOfLines = 1
        modelBadge.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.toolbarModelBadge = modelBadge

        let centerStack = NSStackView(views: [title, modelBadge])
        centerStack.orientation = .horizontal
        centerStack.alignment = .centerY
        centerStack.spacing = 6
        centerStack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        centerStack.translatesAutoresizingMaskIntoConstraints = false

        let centerPill = makeLiquidGlassSurface(
            cornerRadius: 12,
            material: .popover,
            blendingMode: .withinWindow,
            borderAlpha: 0.20,
            tintColor: NSColor(calibratedRed: 0.24, green: 0.12, blue: 0.46, alpha: 0.58),
            borderColorOverride: NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 0.30)
        )
        centerPill.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        centerPill.addSubview(centerStack)
        self.toolbarCenterPill = centerPill

        let quickAskBtn = makeToolbarButton(
            symbol: "bolt.horizontal.circle",
            tooltip: "Tanya Cepat AI / Spotlight (⌘K)",
            action: #selector(openQuickAskPanel)
        )
        let newChatBtn = makeToolbarButton(
            symbol: "square.and.pencil",
            tooltip: "Percakapan Baru (⌘N)",
            action: #selector(menuNewChat)
        )
        let fontDecreaseBtn = makeToolbarButton(
            symbol: "textformat.size.smaller",
            tooltip: "Perkecil Ukuran Font Chat (⌘-)",
            action: #selector(toolbarDecreaseFontSize)
        )
        let fontIncreaseBtn = makeToolbarButton(
            symbol: "textformat.size.larger",
            tooltip: "Perbesar Ukuran Font Chat (⌘+)",
            action: #selector(toolbarIncreaseFontSize)
        )
        let themeBtn = makeToolbarButton(
            symbol: "circle.lefthalf.filled",
            tooltip: "Ganti Tema Gelap / Terang",
            action: #selector(toolbarToggleTheme)
        )
        let qrBtn = makeToolbarButton(
            symbol: "qrcode",
            tooltip: "Akses dari Perangkat Lain (LAN QR)",
            action: #selector(toolbarOpenLanQR)
        )
        let settingsBtn = makeToolbarButton(
            symbol: "slider.horizontal.3",
            tooltip: "Pengaturan Model & Parameter AI (⌘,)",
            action: #selector(menuOpenSettings)
        )
        let inspectorBtn = makeToolbarButton(
            symbol: "sidebar.right",
            tooltip: "Tampilkan/Sembunyikan Inspector (⌘⌥I)",
            action: #selector(menuToggleInspector)
        )
        let aboutBtn = makeToolbarButton(
            symbol: "info.circle",
            tooltip: "Tentang Aplikasi, Cara Kerja & Developer",
            action: #selector(openAboutPanel)
        )
        let reload = makeToolbarButton(
            symbol: "arrow.clockwise",
            tooltip: "Bersihkan cache WebView dan muat ulang (⌘R)",
            action: #selector(clearWebViewCacheAndReload)
        )
        reloadButton = reload

        let browserBtn = makeToolbarButton(
            symbol: "globe",
            tooltip: "Buka Tampilan Ini di Google Chrome / Browser Klien (⌘B)",
            action: #selector(toolbarOpenInBrowser)
        )

        let rightStack = NSStackView(views: [quickAskBtn, newChatBtn, fontDecreaseBtn, fontIncreaseBtn, themeBtn, qrBtn, browserBtn, settingsBtn, inspectorBtn, aboutBtn, reload])
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 4
        rightStack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        let rightPill = makeLiquidGlassSurface(
            cornerRadius: 12,
            material: .popover,
            blendingMode: .withinWindow,
            borderAlpha: 0.22,
            tintColor: NSColor(calibratedRed: 0.24, green: 0.12, blue: 0.46, alpha: 0.62),
            borderColorOverride: NSColor(calibratedRed: 0.72, green: 0.45, blue: 0.98, alpha: 0.28)
        )
        rightPill.addSubview(rightStack)
        self.toolbarRightPill = rightPill

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 0.28).cgColor
        self.toolbarSeparator = separator

        webContentArea = NSView()

        let subviews: [NSView] = [navigationBar, webContentArea]
        for view in subviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        for barSub in [leftPill, centerPill, rightPill, separator] {
            barSub.translatesAutoresizingMaskIntoConstraints = false
            navigationBar.addSubview(barSub)
        }

        let centerX = centerPill.centerXAnchor.constraint(equalTo: navigationBar.centerXAnchor)
        centerX.priority = .defaultHigh

        NSLayoutConstraint.activate([
            navigationBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            navigationBar.topAnchor.constraint(equalTo: container.topAnchor),
            navigationBar.heightAnchor.constraint(equalToConstant: 52),
            webContentArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webContentArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webContentArea.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            webContentArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leftStack.leadingAnchor.constraint(equalTo: leftPill.leadingAnchor),
            leftStack.trailingAnchor.constraint(equalTo: leftPill.trailingAnchor),
            leftStack.topAnchor.constraint(equalTo: leftPill.topAnchor),
            leftStack.bottomAnchor.constraint(equalTo: leftPill.bottomAnchor),
            centerStack.leadingAnchor.constraint(equalTo: centerPill.leadingAnchor),
            centerStack.trailingAnchor.constraint(equalTo: centerPill.trailingAnchor),
            centerStack.topAnchor.constraint(equalTo: centerPill.topAnchor),
            centerStack.bottomAnchor.constraint(equalTo: centerPill.bottomAnchor),
            rightStack.leadingAnchor.constraint(equalTo: rightPill.leadingAnchor),
            rightStack.trailingAnchor.constraint(equalTo: rightPill.trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: rightPill.topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: rightPill.bottomAnchor),
            leftPill.leadingAnchor.constraint(equalTo: navigationBar.leadingAnchor, constant: 78),
            leftPill.centerYAnchor.constraint(equalTo: navigationBar.centerYAnchor),
            centerX,
            centerPill.centerYAnchor.constraint(equalTo: navigationBar.centerYAnchor),
            centerPill.leadingAnchor.constraint(greaterThanOrEqualTo: leftPill.trailingAnchor, constant: 10),
            rightPill.leadingAnchor.constraint(greaterThanOrEqualTo: centerPill.trailingAnchor, constant: 10),
            rightPill.trailingAnchor.constraint(equalTo: navigationBar.trailingAnchor, constant: -16),
            rightPill.centerYAnchor.constraint(equalTo: navigationBar.centerYAnchor),
            modelBadge.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            separator.leadingAnchor.constraint(equalTo: navigationBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: navigationBar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return container
    }

    private func getOrCreateWebView(for appView: AppView) -> WKWebView {
        if let existing = workspaceWebViews[appView.path] {
            return existing
        }
        let newWebView = WKWebView(frame: .zero, configuration: webConfiguration)
        newWebView.uiDelegate = self
        newWebView.navigationDelegate = self
        if #available(macOS 13.3, *) {
            newWebView.isInspectable = true
        }
        newWebView.translatesAutoresizingMaskIntoConstraints = false
        webContentArea.addSubview(newWebView)
        NSLayoutConstraint.activate([
            newWebView.leadingAnchor.constraint(equalTo: webContentArea.leadingAnchor),
            newWebView.trailingAnchor.constraint(equalTo: webContentArea.trailingAnchor),
            newWebView.topAnchor.constraint(equalTo: webContentArea.topAnchor),
            newWebView.bottomAnchor.constraint(equalTo: webContentArea.bottomAnchor),
        ])
        workspaceWebViews[appView.path] = newWebView
        return newWebView
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if message.name == "nativeSpeech" {
                guard message.frameInfo.isMainFrame,
                      let payload = message.body as? [String: Any],
                      let action = payload["action"] as? String else {
                    NSLog("Permintaan pengenalan suara native tidak valid.")
                    return
                }
                if action == "start" {
                    let language = payload["language"] as? String ?? "id-ID"
                    self.startNativeSpeech(language: language)
                } else if action == "stop" {
                    self.stopNativeSpeech()
                } else {
                    NSLog("Aksi pengenalan suara native tidak dikenal: %@", action)
                }
                return
            }
            if message.name == "openExternal" {
                if let urlString = message.body as? String, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            if message.name == "savePng" {
                guard message.frameInfo.isMainFrame else {
                    NSLog("Permintaan simpan PNG dari frame non-utama ditolak.")
                    return
                }
                self.handlePngSaveRequest(message.body)
                return
            }
            if message.name == "saveSvg" {
                guard message.frameInfo.isMainFrame else {
                    NSLog("Permintaan simpan SVG dari frame non-utama ditolak.")
                    return
                }
                self.handleSvgSaveRequest(message.body)
                return
            }
            if message.name == "saveDocument" {
                guard message.frameInfo.isMainFrame else {
                    NSLog("Permintaan simpan dokumen dari frame non-utama ditolak.")
                    return
                }
                self.handleDocumentSaveRequest(message.body)
                return
            }
            if message.name == "aiStatus" {
                guard message.frameInfo.isMainFrame,
                      let payload = message.body as? [String: Any] else { return }
                let isGenerating = payload["isGenerating"] as? Bool ?? false
                let badge = payload["badge"] as? String
                self.updateDockTileStatus(isGenerating: isGenerating, text: badge)
                return
            }
            guard message.name == "appTheme",
                  let theme = message.body as? String,
                  theme == "light" || theme == "dark" else { return }
            let appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)
            message.webView?.appearance = appearance
            if message.webView == self.webView && !self.webContainer.isHidden {
                self.window.appearance = appearance
                self.navigationBar.appearance = appearance
                self.applyToolbarTheme(theme)
            }
        }
    }

    private func applyToolbarTheme(_ theme: String) {
        let isLight = (theme == "light")
        let navBg = isLight
            ? NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.99, alpha: 0.96)
            : NSColor(calibratedRed: 0.095, green: 0.042, blue: 0.23, alpha: 0.92)
        let pillBg = isLight
            ? NSColor.white.withAlphaComponent(0.88)
            : NSColor(calibratedRed: 0.24, green: 0.12, blue: 0.46, alpha: 0.62)
        let pillBorder = isLight
            ? NSColor(calibratedRed: 0.48, green: 0.24, blue: 0.92, alpha: 0.22)
            : NSColor(calibratedRed: 0.72, green: 0.45, blue: 0.98, alpha: 0.30)
        let sepColor = isLight
            ? NSColor(calibratedRed: 0.48, green: 0.24, blue: 0.92, alpha: 0.16)
            : NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 0.28)

        navigationBar?.layer?.backgroundColor = navBg.cgColor
        for pill in [toolbarLeftPill, toolbarCenterPill, toolbarRightPill] {
            pill?.layer?.backgroundColor = pillBg.cgColor
            pill?.layer?.borderColor = pillBorder.cgColor
        }
        toolbarSeparator?.layer?.backgroundColor = sepColor.cgColor
        webTitle?.textColor = isLight
            ? NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.29, alpha: 1.0)
            : .white
        toolbarModelBadge?.textColor = isLight
            ? NSColor(calibratedRed: 0.74, green: 0.10, blue: 0.42, alpha: 0.95)
            : NSColor(calibratedRed: 0.95, green: 0.56, blue: 0.80, alpha: 0.95)
    }

    private func startNativeSpeech(language: String, forceServer: Bool = false) {
        stopNativeSpeech(notifyEnd: false)
        speechGeneration += 1
        let generation = speechGeneration

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable else {
            sendNativeSpeechEvent(type: "error", error: "Pengenalan suara tidak tersedia untuk bahasa \(language).")
            return
        }

        let beginCapture = { [weak self] in
            guard let self, self.speechGeneration == generation else { return }
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.contextualStrings = [
                "EduVis", "Gemma", "AI", "Halo", "Tolong", "Jelaskan",
                "Bagaimana", "Apa", "Terima kasih", "Indonesia"
            ]
            if !forceServer && recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                self.sendNativeSpeechEvent(type: "error", error: "Input mikrofon tidak tersedia.")
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            do {
                try engine.start()
            } catch {
                inputNode.removeTap(onBus: 0)
                self.sendNativeSpeechEvent(type: "error", error: "Tidak dapat memulai mikrofon: \(error.localizedDescription)")
                return
            }

            self.audioEngine = engine
            self.speechRequest = request
            self.speechRecognizer = recognizer
            self.speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.speechGeneration == generation else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.lastSpeechTranscription = text
                        self.sendNativeSpeechEvent(
                            type: "result",
                            transcript: text,
                            isFinal: result.isFinal
                        )
                        // Reset timer keheningan (VAD). Saat pengguna berhenti bicara selama 1.25 detik,
                        // finalisasi teks secara otomatis agar pesan terkirim ke AI.
                        self.speechSilenceTimer?.invalidate()
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.isFinal {
                            self.speechSilenceTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: false) { [weak self] _ in
                                DispatchQueue.main.async {
                                    guard let self, self.speechGeneration == generation else { return }
                                    let finalTranscript = self.lastSpeechTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !finalTranscript.isEmpty {
                                        self.speechRequest?.endAudio()
                                        self.sendNativeSpeechEvent(
                                            type: "result",
                                            transcript: finalTranscript,
                                            isFinal: true
                                        )
                                        self.stopNativeSpeech()
                                    }
                                }
                            }
                        }
                    }
                    if let error {
                        if request.requiresOnDeviceRecognition {
                            NSLog("Pengenalan suara on-device tidak tersedia (%@), fallback ke mode server...", error.localizedDescription)
                            self.speechSilenceTimer?.invalidate()
                            self.speechSilenceTimer = nil
                            self.startNativeSpeech(language: language, forceServer: true)
                            return
                        }
                        self.speechSilenceTimer?.invalidate()
                        self.speechSilenceTimer = nil
                        self.stopNativeSpeech(notifyEnd: false)
                        self.sendNativeSpeechEvent(type: "error", error: "Pengenalan suara: \(error.localizedDescription)")
                    } else if result?.isFinal == true {
                        self.speechSilenceTimer?.invalidate()
                        self.speechSilenceTimer = nil
                        self.stopNativeSpeech()
                    }
                }
            }
            self.sendNativeSpeechEvent(type: "start")
        }

        let requestMicrophone: (@escaping (Bool) -> Void) -> Void = { completion in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                completion(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
            default:
                completion(false)
            }
        }
        let requestSpeechAuthorization = {
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    guard self.speechGeneration == generation else { return }
                    guard status == .authorized else {
                        self.sendNativeSpeechEvent(
                            type: "error",
                            error: "Izin Pengenalan Suara ditolak. Aktifkan di Pengaturan Sistem > Privasi & Keamanan > Pengenalan Suara."
                        )
                        return
                    }
                    requestMicrophone { granted in
                        DispatchQueue.main.async {
                            guard self.speechGeneration == generation else { return }
                            guard granted else {
                                self.sendNativeSpeechEvent(
                                    type: "error",
                                    error: "Izin mikrofon ditolak. Aktifkan EduVis AI Gallery di Pengaturan Sistem > Privasi & Keamanan > Mikrofon."
                                )
                                return
                            }
                            beginCapture()
                        }
                    }
                }
            }
        }
        requestSpeechAuthorization()
    }

    private func stopNativeSpeech(notifyEnd: Bool = true) {
        speechGeneration += 1
        speechSilenceTimer?.invalidate()
        speechSilenceTimer = nil
        lastSpeechTranscription = ""
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        speechRequest?.endAudio()
        speechTask?.cancel()
        audioEngine = nil
        speechRequest = nil
        speechTask = nil
        speechRecognizer = nil
        if notifyEnd {
            sendNativeSpeechEvent(type: "end")
        }
    }

    private func sendNativeSpeechEvent(
        type: String,
        transcript: String? = nil,
        isFinal: Bool? = nil,
        error: String? = nil
    ) {
        var payload: [String: Any] = ["type": type]
        if let transcript { payload["transcript"] = transcript }
        if let isFinal { payload["isFinal"] = isFinal }
        if let error { payload["error"] = error }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else {
            NSLog("Tidak dapat menyiapkan peristiwa pengenalan suara native.")
            return
        }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('native-speech-event', { detail: \(json) }));"
        ) { _, error in
            if let error {
                NSLog("Tidak dapat mengirim peristiwa pengenalan suara ke WebView: %@", error.localizedDescription)
            }
        }
    }

    private func handlePngSaveRequest(_ body: Any) {
        guard let payload = body as? [String: Any],
              let requestID = payload["requestID"] as? String,
              requestID.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
            NSLog("Permintaan simpan PNG tidak memiliki ID valid.")
            return
        }

        guard let filename = payload["filename"] as? String,
              let base64 = payload["base64"] as? String,
              base64.utf8.count <= 70 * 1024 * 1024,
              let imageData = Data(base64Encoded: base64),
              imageData.count >= 8,
              imageData.count <= 50 * 1024 * 1024,
              imageData.prefix(8).elementsEqual([UInt8](arrayLiteral: 137, 80, 78, 71, 13, 10, 26, 10)) else {
            reportPngSaveCompletion(
                requestID: requestID,
                status: "error",
                detail: "Data PNG tidak valid atau melebihi batas ukuran 50 MB."
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).lastPathComponent
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .OK, let destination = panel.url else {
                self.reportPngSaveCompletion(requestID: requestID, status: "cancelled")
                return
            }

            do {
                try imageData.write(to: destination, options: .atomic)
                self.reportPngSaveCompletion(requestID: requestID, status: "saved")
            } catch {
                self.reportPngSaveCompletion(
                    requestID: requestID,
                    status: "error",
                    detail: error.localizedDescription
                )
                let alert = NSAlert()
                alert.messageText = "Tidak dapat menyimpan PNG"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: self.window)
            }
        }
    }

    private func handleSvgSaveRequest(_ body: Any) {
        guard let payload = body as? [String: Any],
              let requestID = payload["requestID"] as? String,
              requestID.range(of: "^[A-Za-z0-9_-]{1,96}$", options: .regularExpression) != nil else {
            NSLog("Permintaan simpan SVG tidak memiliki ID valid.")
            return
        }

        guard let filename = payload["filename"] as? String,
              let markup = payload["markup"] as? String,
              let data = markup.data(using: .utf8),
              data.count <= 20 * 1024 * 1024,
              markup.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg"),
              markup.contains("</svg>"),
              !markup.localizedCaseInsensitiveContains("<!doctype"),
              !markup.localizedCaseInsensitiveContains("<!entity") else {
            reportSvgSaveCompletion(
                requestID: requestID,
                status: "error",
                detail: "Data SVG tidak valid atau melebihi batas ukuran 20 MB."
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).lastPathComponent
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .OK, let destination = panel.url else {
                self.reportSvgSaveCompletion(requestID: requestID, status: "cancelled")
                return
            }

            do {
                try data.write(to: destination, options: .atomic)
                self.reportSvgSaveCompletion(requestID: requestID, status: "saved")
            } catch {
                self.reportSvgSaveCompletion(
                    requestID: requestID,
                    status: "error",
                    detail: error.localizedDescription
                )
                let alert = NSAlert()
                alert.messageText = "Tidak dapat menyimpan SVG"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: self.window)
            }
        }
    }

    private func handleDocumentSaveRequest(_ body: Any) {
        guard let payload = body as? [String: Any],
              let requestID = payload["requestID"] as? String,
              requestID.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else {
            NSLog("Permintaan simpan dokumen tidak memiliki ID yang valid.")
            return
        }
        guard
              let filename = payload["filename"] as? String,
              let rawMimeType = payload["mimeType"] as? String,
              let base64 = payload["base64"] as? String,
              let data = Data(base64Encoded: base64),
              data.count > 0,
              data.count <= 200 * 1024 * 1024 else {
            reportDocumentSaveCompletion(
                requestID: requestID,
                status: "error",
                detail: "Data dokumen tidak valid atau melebihi batas ukuran."
            )
            return
        }
        NSLog("Menerima permintaan simpan %@ (%lld byte).", filename, Int64(data.count))

        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let contentType: UTType
        if ext == "pdf" {
            contentType = .pdf
        } else if ext == "docx" {
            contentType = UTType(filenameExtension: "docx") ?? .data
        } else if ext == "wav" {
            contentType = UTType(filenameExtension: "wav") ?? .audio
        } else if ext == "md" || ext == "markdown" {
            contentType = UTType(filenameExtension: "md") ?? .plainText
        } else if ext == "txt" {
            contentType = .plainText
        } else if let detected = UTType(mimeType: rawMimeType) {
            contentType = detected
        } else {
            contentType = .data
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).lastPathComponent

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let destination = panel.url else {
                self.reportDocumentSaveCompletion(requestID: requestID, status: "cancelled")
                return
            }

            do {
                try data.write(to: destination, options: .atomic)
                self.reportDocumentSaveCompletion(requestID: requestID, status: "saved")
            } catch {
                self.reportDocumentSaveCompletion(
                    requestID: requestID,
                    status: "error",
                    detail: error.localizedDescription
                )
                let alert = NSAlert()
                alert.messageText = "Tidak dapat menyimpan dokumen"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: self.window)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        if window.isVisible && window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            panel.begin(completionHandler: handleResponse)
        }
    }

    private func reportSvgSaveCompletion(
        requestID: String,
        status: String,
        detail: String? = nil
    ) {
        var arguments = [requestID, status]
        if let detail { arguments.append(detail) }
        guard let json = try? JSONSerialization.data(
            withJSONObject: arguments,
            options: [.fragmentsAllowed]
        ), let encodedArguments = String(data: json, encoding: .utf8) else {
            NSLog("Tidak dapat menyiapkan status dialog simpan SVG.")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.webView.evaluateJavaScript(
                "window.__nativeSvgSaveComplete?.(...\(encodedArguments))"
            ) { _, error in
                if let error {
                    NSLog("Tidak dapat mengirim status simpan SVG ke WebView: %@", error.localizedDescription)
                }
            }
        }
    }

    private func reportPngSaveCompletion(
        requestID: String,
        status: String,
        detail: String? = nil
    ) {
        var arguments = [requestID, status]
        if let detail { arguments.append(detail) }
        guard let json = try? JSONSerialization.data(
            withJSONObject: arguments,
            options: [.fragmentsAllowed]
        ), let encodedArguments = String(data: json, encoding: .utf8) else {
            NSLog("Tidak dapat menyiapkan status dialog simpan PNG.")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.webView.evaluateJavaScript(
                "window.__nativePngSaveComplete?.(...\(encodedArguments))"
            ) { _, error in
                if let error {
                    NSLog("Tidak dapat mengirim status simpan PNG ke WebView: %@", error.localizedDescription)
                }
            }
        }
    }

    private func reportDocumentSaveCompletion(
        requestID: String,
        status: String,
        detail: String? = nil
    ) {
        var arguments = [requestID, status]
        if let detail { arguments.append(detail) }
        guard let json = try? JSONSerialization.data(
            withJSONObject: arguments,
            options: [.fragmentsAllowed]
        ), let encodedArguments = String(data: json, encoding: .utf8) else {
            NSLog("Tidak dapat menyiapkan status dialog simpan dokumen.")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.webView.evaluateJavaScript(
                "window.__nativeDocumentSaveComplete?.(...\(encodedArguments))"
            ) { _, error in
                if let error {
                    NSLog("Tidak dapat mengirim status simpan dokumen ke WebView: %@", error.localizedDescription)
                }
            }
        }
    }

    @objc private func openSelectedView() {
        let selection = min(max(viewPicker.indexOfSelectedItem, 0), appViews.count - 1)
        let appView = appViews[selection]
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            NSLog("URL aplikasi tidak valid.")
            return
        }
        components.path = "/" + appView.path
        components.queryItems = (components.queryItems ?? [])
            .filter { $0.name != "model" }
        if let selectedModelID {
            components.queryItems?.append(URLQueryItem(name: "model", value: selectedModelID))
        }
        guard let url = components.url else {
            NSLog("Tidak dapat membuat URL untuk tampilan \(appView.title).")
            return
        }

        webTitle.stringValue = appView.title
        toolbarWorkspacePicker?.selectItem(at: selection)
        toolbarModelBadge?.stringValue = selectedModelID.map { "·  \($0)" } ?? ""
        window.title = appName

        // Instant Workspace Switching: activate cached WKWebView or initialize if first time
        let targetWebView = getOrCreateWebView(for: appView)
        for (path, wv) in workspaceWebViews {
            wv.isHidden = (path != appView.path)
        }
        self.webView = targetWebView

        if targetWebView.url == nil {
            targetWebView.load(URLRequest(url: url))
        } else if let currentURL = targetWebView.url,
                  currentURL.path != url.path || currentURL.query != url.query {
            targetWebView.load(URLRequest(url: url))
        }

        launcherView.isHidden = true
        webContainer.isHidden = false
        syncAppearanceWithActiveWebView()
        updateStatusItemModel()
    }

    private func syncAppearanceWithActiveWebView() {
        webView?.evaluateJavaScript("""
        (() => {
            if (!document.body) return;
            const isLight = document.body.classList.contains('light-theme') ||
                document.documentElement.getAttribute('data-theme') === 'light';
            const theme = isLight ? 'light' : 'dark';
            window.webkit?.messageHandlers?.appTheme?.postMessage(theme);
        })();
        """, completionHandler: nil)
    }

    @objc private func showLauncher() {
        // Keep webView running in background so active chats/tasks are not interrupted
        webContainer.isHidden = true
        launcherView.isHidden = false
        window.appearance = nil
        window.title = appName
        updateStatusItemModel()
    }

    @objc private func clearWebViewCacheAndReload() {
        guard let currentWebView = webView, currentWebView.url != nil else { return }
        reloadButton.isEnabled = false

        let cacheTypes = Set([
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
        ])
        currentWebView.configuration.websiteDataStore.removeData(
            ofTypes: cacheTypes,
            modifiedSince: .distantPast
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.webView?.reloadFromOrigin()
                self.reloadButton.isEnabled = true
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let appIcon = NSApp.applicationIconImage?.copy() as? NSImage {
                appIcon.size = NSSize(width: 18, height: 18)
                button.image = appIcon
                button.imagePosition = .imageLeading
                button.title = " Gemma"
            } else {
                button.title = "✦ Gemma"
            }
            button.toolTip = "Gemma Studio Native Control"
        }
        self.statusItem = item
        updateStatusItemModel()
    }

    private func updateStatusItemModel() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Gemma Local AI Studio", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let modelTitle = selectedModelID ?? "Belum ada model aktif"
        let ramGB = Int(round(getPhysicalMemoryGB()))
        let modelItem = NSMenuItem(title: "Model: \(modelTitle)", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        let rssInfo = litertMemoryMB > 0
            ? String(format: " · LiteRT: %.0f MB", litertMemoryMB)
            : ""
        let ramItem = NSMenuItem(title: "RAM: \(ramGB) GB Unified Memory\(rssInfo)", action: nil, keyEquivalent: "")
        ramItem.isEnabled = false
        menu.addItem(ramItem)

        let cachedCount = workspaceWebViews.count
        let cacheItem = NSMenuItem(title: "Ruang Kerja Aktif di Memori: \(cachedCount) / \(appViews.count)", action: nil, keyEquivalent: "")
        cacheItem.isEnabled = false
        menu.addItem(cacheItem)

        menu.addItem(NSMenuItem.separator())

        let quickAskItem = NSMenuItem(title: "⚡ Tanya Cepat AI (Quick Ask)…", action: #selector(openQuickAskPanel), keyEquivalent: "k")
        quickAskItem.target = self
        menu.addItem(quickAskItem)

        let showWindowItem = NSMenuItem(title: "Tampilkan Jendela Utama", action: #selector(menuShowMainWindow), keyEquivalent: "")
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        let workspaceMenu = NSMenu()
        for (index, appView) in appViews.enumerated() {
            let keyEq = index < 9 ? "\(index + 1)" : "\(index - 8)"
            let wsItem = NSMenuItem(title: appView.title, action: #selector(menuOpenWorkspace(_:)), keyEquivalent: keyEq)
            if index >= 9 {
                wsItem.keyEquivalentModifierMask = [.command, .option]
            }
            wsItem.tag = index
            wsItem.target = self
            if !webContainer.isHidden && viewPicker.indexOfSelectedItem == index {
                wsItem.state = .on
            }
            workspaceMenu.addItem(wsItem)
        }
        let workspaceParent = NSMenuItem(title: "Buka Workspace (\(appViews.count) Ruang)", action: nil, keyEquivalent: "")
        workspaceParent.submenu = workspaceMenu
        menu.addItem(workspaceParent)

        menu.addItem(NSMenuItem.separator())

        let refreshMemItem = NSMenuItem(title: "Segarkan Memori Model (Restart LiteRT-LM)", action: #selector(menuRefreshModelMemory), keyEquivalent: "")
        refreshMemItem.target = self
        menu.addItem(refreshMemItem)

        let purgeTabsItem = NSMenuItem(title: "Bebaskan Memori Tab Tidak Aktif", action: #selector(menuPurgeInactiveWebViews), keyEquivalent: "")
        purgeTabsItem.target = self
        menu.addItem(purgeTabsItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Pengaturan Model LiteRT-LM…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let launcherItem = NSMenuItem(title: "Pusat Model & Pengaturan…", action: #selector(menuShowLauncher), keyEquivalent: "")
        launcherItem.target = self
        menu.addItem(launcherItem)

        let storageItem = NSMenuItem(title: "Kelola Penyimpanan Model (OPFS)…", action: #selector(menuOpenStorageManager), keyEquivalent: "s")
        storageItem.target = self
        menu.addItem(storageItem)

        menu.addItem(NSMenuItem.separator())

        let reloadItem = NSMenuItem(title: "Muat Ulang Halaman Saat Ini", action: #selector(clearWebViewCacheAndReload), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let browserItem = NSMenuItem(title: "Buka di Browser Eksternal…", action: #selector(menuOpenBrowser), keyEquivalent: "b")
        browserItem.target = self
        menu.addItem(browserItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Keluar dari Gemma Studio", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func menuOpenWorkspace(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0 && index < appViews.count else { return }
        viewPicker.selectItem(at: index)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        openSelectedView()
    }

    @objc private func menuShowLauncher() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        showLauncher()
    }

    func updateDockTileStatus(isGenerating: Bool, text: String? = nil) {
        DispatchQueue.main.async {
            if isGenerating {
                NSApp.dockTile.badgeLabel = text ?? "⚡ AI"
            } else {
                NSApp.dockTile.badgeLabel = nil
            }
        }
    }

    @objc private func menuOpenSettings() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webContainer.isHidden {
            openSelectedView()
        }
        webView?.evaluateJavaScript("""
        (() => {
            if (typeof openAISettingsModal === 'function') {
                openAISettingsModal();
                return;
            }
            const modal = document.getElementById('ai-settings-modal');
            if (modal) modal.classList.remove('hidden');
        })();
        """, completionHandler: nil)
    }

    @objc private func menuOpenStorageManager() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webContainer.isHidden {
            openSelectedView()
        }
        webView?.evaluateJavaScript("if (window.GemmaStorageManager) window.GemmaStorageManager.openStorageModal();", completionHandler: nil)
    }

    @objc private func menuToggleInspector() {
        webView?.evaluateJavaScript("if (window.MacSplitView) window.MacSplitView.toggleInspector();", completionHandler: nil)
    }

    @objc private func menuToggleSidebar() {
        webView?.evaluateJavaScript("""
        (() => {
            if (typeof toggleSidebar === 'function') {
                toggleSidebar();
                return;
            }
            if (window.MacSplitView && typeof window.MacSplitView.toggleSidebar === 'function') {
                window.MacSplitView.toggleSidebar();
                return;
            }
            const sidebar = document.querySelector('aside.sidebar, .sidebar, #sidebar');
            if (sidebar) sidebar.classList.toggle('hidden');
        })();
        """, completionHandler: nil)
    }

    @objc private func toolbarWorkspaceChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < appViews.count else { return }
        viewPicker.selectItem(at: index)
        openSelectedView()
    }

    private func evaluateFontSizeAction(_ script: String) {
        webView?.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, let size = result as? NSNumber else { return }
            let sizeText = size.doubleValue.truncatingRemainder(dividingBy: 1) == 0
                ? "\(size.intValue)px"
                : String(format: "%.1fpx", size.doubleValue)
            DispatchQueue.main.async {
                let modelPrefix = self.selectedModelID.map { "·  \($0)  ·  " } ?? "·  "
                self.toolbarModelBadge?.stringValue = "\(modelPrefix)\(sizeText)"
            }
        }
    }

    @objc private func toolbarDecreaseFontSize() {
        evaluateFontSizeAction("""
        (() => {
            if (typeof window.expandChatFontSizeWidget === 'function') window.expandChatFontSizeWidget();
            if (typeof window.decreaseChatFontSize === 'function') return window.decreaseChatFontSize();
            return null;
        })();
        """)
    }

    @objc private func toolbarIncreaseFontSize() {
        evaluateFontSizeAction("""
        (() => {
            if (typeof window.expandChatFontSizeWidget === 'function') window.expandChatFontSizeWidget();
            if (typeof window.increaseChatFontSize === 'function') return window.increaseChatFontSize();
            return null;
        })();
        """)
    }

    @objc private func toolbarResetFontSize() {
        evaluateFontSizeAction("""
        (() => {
            if (typeof window.expandChatFontSizeWidget === 'function') window.expandChatFontSizeWidget();
            if (typeof window.resetChatFontSize === 'function') return window.resetChatFontSize();
            return null;
        })();
        """)
    }

    @objc private func toolbarToggleTheme() {
        webView?.evaluateJavaScript("""
        (() => {
            if (typeof toggleTheme === 'function') {
                toggleTheme();
            } else {
                const btn = document.querySelector('#themeBtn, #themeToggle, #theme-toggle-btn, #theme-toggle, #themeButton, button[onclick*="toggleTheme"], button[onclick*="Theme"]');
                if (btn) btn.click();
                else document.body.classList.toggle('light-theme');
            }
            const isLight = document.body.classList.contains('light-theme') ||
                document.documentElement.getAttribute('data-theme') === 'light';
            window.webkit?.messageHandlers?.appTheme?.postMessage(isLight ? 'light' : 'dark');
        })();
        """, completionHandler: nil)
    }

    @objc private func toolbarOpenInBrowser() {
        if let currentURL = webView?.url {
            NSWorkspace.shared.open(currentURL)
        } else if let base = baseURL {
            NSWorkspace.shared.open(base)
        }
    }

    @objc private func toolbarOpenLanQR() {
        if webContainer.isHidden {
            openNativeLanQRPanel()
            return
        }
        webView?.evaluateJavaScript("""
        (() => {
            if (window.GemmaLanQR && typeof window.GemmaLanQR.openModal === 'function') {
                window.GemmaLanQR.openModal();
                return;
            }
            const btn = document.querySelector('#lan-qr-open, #lan-qr-trigger-btn, button[onclick*="openLanQr"], button[onclick*="LanQr"]');
            if (btn) {
                btn.click();
                return;
            }
            const ensureScript = (src) => new Promise((resolve, reject) => {
                if (document.querySelector(`script[src*="${src}"]`)) return resolve();
                const s = document.createElement('script');
                s.src = src;
                s.onload = () => resolve();
                s.onerror = (e) => reject(e);
                document.head.appendChild(s);
            });
            ensureScript('/nano_asset/assets/js/qrcode-generator.js')
                .then(() => ensureScript('/nano_asset/assets/js/lan-qrcode.js'))
                .then(() => {
                    if (window.GemmaLanQR && typeof window.GemmaLanQR.openModal === 'function') {
                        window.GemmaLanQR.openModal();
                    } else {
                        document.getElementById('lan-qr-open')?.click();
                    }
                })
                .catch(err => console.error('Gagal memuat modul QR LAN:', err));
        })();
        """, completionHandler: nil)
    }

    @objc private func menuNewChat() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webContainer.isHidden {
            openSelectedView()
        }
        webView?.evaluateJavaScript("""
        (() => {
            if (typeof clearCurrentConversation === 'function') clearCurrentConversation();
            else if (typeof resetChat === 'function') resetChat();
            else if (typeof newSession === 'function') newSession();
            else if (typeof clearChatHistory === 'function') clearChatHistory();
            else {
                const btn = document.querySelector('#newChat, #new-chat-btn, .btn-new-chat, button[onclick*="resetChat"], button[title*="Baru"]');
                if (btn) btn.click();
            }
        })();
        """, completionHandler: nil)
    }

    @objc private func menuFindInPage() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webContainer.isHidden {
            openSelectedView()
        }
        webView?.evaluateJavaScript("""
        (() => {
            const searchInput = document.querySelector('#session-search-input, #search-input, input[type="search"], input[placeholder*="Cari"]');
            if (searchInput) {
                searchInput.focus();
                searchInput.select();
            }
        })();
        """, completionHandler: nil)
    }

    @objc private func menuExportDocument() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webContainer.isHidden {
            openSelectedView()
        }
        webView?.evaluateJavaScript("""
        (() => {
            if (window.GemmaExport && typeof window.GemmaExport.openExportModal === 'function') {
                window.GemmaExport.openExportModal();
            } else {
                const btn = document.querySelector('button[title*="Ekspor"], .btn-export');
                if (btn) btn.click();
            }
        })();
        """, completionHandler: nil)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dockMenu = NSMenu()

        let modelTitle = selectedModelID ?? "Belum ada model aktif"
        let statusItem = NSMenuItem(title: "Model: \(modelTitle)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        dockMenu.addItem(statusItem)

        let ramGB = Int(round(getPhysicalMemoryGB()))
        let rssInfo = litertMemoryMB > 0 ? String(format: " · LiteRT %.0f MB", litertMemoryMB) : ""
        let memItem = NSMenuItem(title: "RAM: \(ramGB) GB Unified\(rssInfo)", action: nil, keyEquivalent: "")
        memItem.isEnabled = false
        dockMenu.addItem(memItem)
        dockMenu.addItem(NSMenuItem.separator())

        let quickAskItem = NSMenuItem(title: "⚡ Tanya Cepat AI (Quick Ask)…", action: #selector(openQuickAskPanel), keyEquivalent: "")
        quickAskItem.target = self
        dockMenu.addItem(quickAskItem)

        let newChatItem = NSMenuItem(title: "Percakapan Baru", action: #selector(menuNewChat), keyEquivalent: "")
        newChatItem.target = self
        dockMenu.addItem(newChatItem)

        let wsMenu = NSMenu()
        for (index, appView) in appViews.enumerated() {
            let item = NSMenuItem(title: appView.title, action: #selector(menuOpenWorkspace(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            if !webContainer.isHidden && viewPicker.indexOfSelectedItem == index {
                item.state = .on
            }
            wsMenu.addItem(item)
        }
        let wsParent = NSMenuItem(title: "Buka Ruang Kerja (\(appViews.count))", action: nil, keyEquivalent: "")
        wsParent.submenu = wsMenu
        dockMenu.addItem(wsParent)
        dockMenu.addItem(NSMenuItem.separator())

        let refreshMemItem = NSMenuItem(title: "Segarkan Memori Model (Bebaskan RAM)", action: #selector(menuRefreshModelMemory), keyEquivalent: "")
        refreshMemItem.target = self
        dockMenu.addItem(refreshMemItem)

        let storageItem = NSMenuItem(title: "Kelola Penyimpanan Model (OPFS)…", action: #selector(menuOpenStorageManager), keyEquivalent: "")
        storageItem.target = self
        dockMenu.addItem(storageItem)

        return dockMenu
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let aboutItem = NSMenuItem(title: "Tentang \(appName) & Developer…", action: #selector(openAboutPanel), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        let quickAskAppItem = NSMenuItem(title: "⚡ Tanya Cepat AI (Quick Ask)…", action: #selector(openQuickAskPanel), keyEquivalent: "k")
        quickAskAppItem.target = self
        appMenu.addItem(quickAskAppItem)
        let launcherMenuItem = NSMenuItem(title: "Peluncur Ruang Kerja…", action: #selector(menuShowLauncher), keyEquivalent: "")
        launcherMenuItem.target = self
        appMenu.addItem(launcherMenuItem)
        let settingsItem = NSMenuItem(title: "Pengaturan Model LiteRT-LM…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        let servicesItem = NSMenuItem(title: "Layanan", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Sembunyikan \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Sembunyikan Lainnya", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Tampilkan Semua", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Keluar dari \(appName)", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "Berkas")
        fileMenuItem.submenu = fileMenu
        let newChatItem = NSMenuItem(title: "Percakapan Baru", action: #selector(menuNewChat), keyEquivalent: "n")
        newChatItem.target = self
        fileMenu.addItem(newChatItem)
        let quickAskFileItem = NSMenuItem(title: "Tanya Cepat AI (Spotlight)…", action: #selector(openQuickAskPanel), keyEquivalent: " ")
        quickAskFileItem.keyEquivalentModifierMask = [.command, .option]
        quickAskFileItem.target = self
        fileMenu.addItem(quickAskFileItem)
        let exportItem = NSMenuItem(title: "Simpan & Ekspor Dokumen…", action: #selector(menuExportDocument), keyEquivalent: "e")
        exportItem.target = self
        fileMenu.addItem(exportItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Sembunyikan Jendela", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Pilih Semua", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        let findItem = NSMenuItem(title: "Cari dalam Percakapan…", action: #selector(menuFindInPage), keyEquivalent: "f")
        findItem.target = self
        editMenu.addItem(findItem)

        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "Tampilan")
        viewMenuItem.submenu = viewMenu
        let wsMenu = NSMenu(title: "Ruang Kerja")
        for (index, appView) in appViews.enumerated() {
            let keyEq = index < 9 ? "\(index + 1)" : "\(index - 8)"
            let item = NSMenuItem(title: appView.title, action: #selector(menuOpenWorkspace(_:)), keyEquivalent: keyEq)
            if index >= 9 {
                item.keyEquivalentModifierMask = [.command, .option]
            }
            item.tag = index
            item.target = self
            wsMenu.addItem(item)
        }
        let wsParent = NSMenuItem(title: "Pilih Ruang Kerja (\(appViews.count))", action: nil, keyEquivalent: "")
        wsParent.submenu = wsMenu
        viewMenu.addItem(wsParent)
        viewMenu.addItem(NSMenuItem.separator())
        let sidebarItem = NSMenuItem(title: "Tampilkan/Sembunyikan Sidebar", action: #selector(menuToggleSidebar), keyEquivalent: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .option]
        sidebarItem.target = self
        viewMenu.addItem(sidebarItem)
        let inspectorItem = NSMenuItem(title: "Tampilkan/Sembunyikan Inspector", action: #selector(menuToggleInspector), keyEquivalent: "i")
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        inspectorItem.target = self
        viewMenu.addItem(inspectorItem)
        viewMenu.addItem(NSMenuItem.separator())
        let increaseFontItem = NSMenuItem(title: "Perbesar Ukuran Font Chat", action: #selector(toolbarIncreaseFontSize), keyEquivalent: "+")
        increaseFontItem.keyEquivalentModifierMask = [.command]
        increaseFontItem.target = self
        viewMenu.addItem(increaseFontItem)
        let decreaseFontItem = NSMenuItem(title: "Perkecil Ukuran Font Chat", action: #selector(toolbarDecreaseFontSize), keyEquivalent: "-")
        decreaseFontItem.keyEquivalentModifierMask = [.command]
        decreaseFontItem.target = self
        viewMenu.addItem(decreaseFontItem)
        let resetFontItem = NSMenuItem(title: "Reset Ukuran Font Chat (15px)", action: #selector(toolbarResetFontSize), keyEquivalent: "0")
        resetFontItem.keyEquivalentModifierMask = [.command, .shift]
        resetFontItem.target = self
        viewMenu.addItem(resetFontItem)
        viewMenu.addItem(NSMenuItem.separator())
        let launcherItem = NSMenuItem(title: "Pusat Model & Pengaturan…", action: #selector(menuShowLauncher), keyEquivalent: "0")
        launcherItem.target = self
        viewMenu.addItem(launcherItem)
        let storageItem = NSMenuItem(title: "Kelola Penyimpanan Model (OPFS)…", action: #selector(menuOpenStorageManager), keyEquivalent: "s")
        storageItem.target = self
        viewMenu.addItem(storageItem)
        let refreshMemViewItem = NSMenuItem(title: "Segarkan Memori Model (Restart LiteRT-LM)", action: #selector(menuRefreshModelMemory), keyEquivalent: "m")
        refreshMemViewItem.keyEquivalentModifierMask = [.command, .option]
        refreshMemViewItem.target = self
        viewMenu.addItem(refreshMemViewItem)
        let purgeTabsViewItem = NSMenuItem(title: "Bebaskan Memori Tab Tidak Aktif", action: #selector(menuPurgeInactiveWebViews), keyEquivalent: "")
        purgeTabsViewItem.target = self
        viewMenu.addItem(purgeTabsViewItem)
        viewMenu.addItem(NSMenuItem.separator())
        let reloadItem = NSMenuItem(title: "Muat Ulang Halaman Saat Ini", action: #selector(clearWebViewCacheAndReload), keyEquivalent: "r")
        reloadItem.target = self
        viewMenu.addItem(reloadItem)
        let browserItem = NSMenuItem(title: "Buka di Browser Eksternal…", action: #selector(menuOpenBrowser), keyEquivalent: "b")
        browserItem.target = self
        viewMenu.addItem(browserItem)
        viewMenu.addItem(NSMenuItem.separator())
        let fullScreenItem = NSMenuItem(title: "Masuk Layar Penuh", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)

        // 5. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Jendela")
        windowMenuItem.submenu = windowMenu
        let showMainWinItem = NSMenuItem(title: "Tampilkan Jendela Utama \(appName)", action: #selector(menuShowMainWindow), keyEquivalent: "1")
        showMainWinItem.keyEquivalentModifierMask = [.command, .shift]
        showMainWinItem.target = self
        windowMenu.addItem(showMainWinItem)
        windowMenu.addItem(withTitle: "Minimalkan", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Perbesar", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bawa Semua ke Depan", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // 6. Help Menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Bantuan")
        helpMenuItem.submenu = helpMenu
        let guideItem = NSMenuItem(title: "Tentang Aplikasi, Cara Kerja & Developer…", action: #selector(openAboutPanel), keyEquivalent: "?")
        guideItem.target = self
        helpMenu.addItem(guideItem)
        let helpItem = NSMenuItem(title: "Buka Dokumentasi di Browser…", action: #selector(menuOpenBrowser), keyEquivalent: "")
        helpItem.target = self
        helpMenu.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func menuShowMainWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuOpenBrowser() {
        NSWorkspace.shared.open(baseURL)
    }

    @objc private func menuQuit() {
        isTerminatingApp = true
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == window && !isTerminatingApp {
            // Standar macOS: ⌘W / tombol merah menyembunyikan jendela utama tanpa mematikan server model AI
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        guard let firstURL = urls.first else { return }
        let ext = firstURL.pathExtension.lowercased()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if ext == "litertlm" {
            openModelCenter()
            importModel(from: firstURL)
            return
        }

        if ["png", "jpg", "jpeg", "webp", "gif"].contains(ext) {
            if let visionIdx = appViews.firstIndex(where: { $0.path == "vision_ulti.html" }) {
                viewPicker.selectItem(at: visionIdx)
                openSelectedView()
            }
            return
        }

        if ["py", "js", "ts", "swift", "html", "css", "json", "sql", "sh"].contains(ext) {
            if let codeIdx = appViews.firstIndex(where: { $0.path == "analisis-kode.html" }) {
                viewPicker.selectItem(at: codeIdx)
                openSelectedView()
            }
            if let textContent = try? String(contentsOf: firstURL, encoding: .utf8) {
                let preview = String(textContent.prefix(6000))
                openQuickAskWithText("Analisis file kode `\(firstURL.lastPathComponent)` berikut:\n\n```\n\(preview)\n```")
            }
            return
        }

        if let tanyaIdx = appViews.firstIndex(where: { $0.path == "tanya-ai-standalone.html" }) {
            viewPicker.selectItem(at: tanyaIdx)
            openSelectedView()
        }
        if ["txt", "md", "csv"].contains(ext),
           let textContent = try? String(contentsOf: firstURL, encoding: .utf8) {
            let preview = String(textContent.prefix(6000))
            openQuickAskWithText("Ringkas dan jelaskan isi dokumen `\(firstURL.lastPathComponent)` berikut:\n\n\(preview)")
        }
    }

    @objc func handleSystemServicePrompt(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.openQuickAskWithText("Jelaskan atau ringkas teks berikut secara jelas:\n\n\"\(selectedText)\"")
        }
    }

    private func openQuickAskWithText(_ text: String) {
        openQuickAskPanel()
        quickAskInput?.stringValue = text
        submitQuickAskPrompt()
    }

    @objc private func openQuickAskPanel() {
        if quickAskPanel == nil {
            makeQuickAskPanel()
        }
        quickAskPanel?.center()
        quickAskPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let input = quickAskInput {
            quickAskPanel?.makeFirstResponder(input)
        }
    }

    private func makeQuickAskPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "⚡ Tanya Cepat AI — Gemma 4 Spotlight (⌘K)"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let glassBackground = NSVisualEffectView()
        glassBackground.material = .popover
        glassBackground.blendingMode = .behindWindow
        glassBackground.state = .active
        glassBackground.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Tanya Cepat ke Gemma 4 Lokal + Knowledge Base")
        header.font = .systemFont(ofSize: 14, weight: .bold)
        header.textColor = .labelColor

        let subheader = NSTextField(
            wrappingLabelWithString: "Ketik pertanyaan singkat dari mana saja (⌘K atau ⌥⌘Space), tekan Enter untuk jawaban instan, atau teruskan ke ruang kerja utama."
        )
        subheader.font = .systemFont(ofSize: 11.5)
        subheader.textColor = .secondaryLabelColor

        let input = NSTextField()
        input.placeholderString = "Tanyakan apa saja ke Gemma 4 lokal… (Tekan Enter)"
        input.font = .systemFont(ofSize: 13.5)
        input.controlSize = .large
        input.target = self
        input.action = #selector(submitQuickAskPrompt)
        self.quickAskInput = input

        let askBtn = NSButton(title: "Tanya Cepat ↵", target: self, action: #selector(submitQuickAskPrompt))
        askBtn.bezelStyle = .rounded
        askBtn.keyEquivalent = "\r"
        self.quickAskSendButton = askBtn

        let forwardBtn = NSButton(title: "Buka di Ruang Kerja →", target: self, action: #selector(forwardQuickAskToWorkspace))
        forwardBtn.bezelStyle = .rounded

        let copyBtn = NSButton(title: "Salin Jawaban", target: self, action: #selector(copyQuickAskAnswer))
        copyBtn.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [askBtn, forwardBtn, copyBtn])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let status = NSTextField(labelWithString: "Siap menjawab secara offline di perangkat Anda.")
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = .secondaryLabelColor
        self.quickAskStatusLabel = status

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.string = "Jawaban AI akan muncul di sini…"
        scrollView.documentView = textView
        self.quickAskAnswerView = textView

        let answerGlassCard = makeLiquidGlassSurface(
            cornerRadius: 14,
            material: .contentBackground,
            blendingMode: .withinWindow,
            borderAlpha: 0.16
        )
        answerGlassCard.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: answerGlassCard.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: answerGlassCard.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: answerGlassCard.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: answerGlassCard.bottomAnchor),
            answerGlassCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])

        let stack = NSStackView(views: [header, subheader, input, buttonRow, status, answerGlassCard])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let contentView = panel.contentView {
            contentView.addSubview(glassBackground)
            contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                glassBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                glassBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                glassBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
                glassBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            ])
        }
        self.quickAskPanel = panel
    }

    @objc private func submitQuickAskPrompt() {
        guard let prompt = quickAskInput?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            quickAskStatusLabel?.stringValue = "Masukkan pertanyaan terlebih dahulu."
            return
        }
        guard let url = modelAPIURL(path: "/api/automation/webhook") else {
            quickAskStatusLabel?.stringValue = "Endpoint lokal tidak valid."
            return
        }

        quickAskSendButton?.isEnabled = false
        quickAskStatusLabel?.stringValue = "⚡ Memproses dengan Gemma 4 lokal…"
        quickAskAnswerView?.string = "Sedang berpikir…"
        updateDockTileStatus(isGenerating: true, text: "⚡ AI")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "prompt": prompt,
            "model": selectedModelID ?? "auto",
            "use_kb": true,
            "max_tokens": 768,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        modelSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.quickAskSendButton?.isEnabled = true
                self.updateDockTileStatus(isGenerating: false)
                if let error {
                    self.quickAskStatusLabel?.stringValue = "Gagal menghubungi model: \(error.localizedDescription)"
                    self.quickAskAnswerView?.string = "Pastikan minimal 1 model .litertlm sudah diimpor di Pusat Model."
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, let data else {
                    self.quickAskStatusLabel?.stringValue = "Respons model tidak valid."
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.quickAskStatusLabel?.stringValue = "Gagal mengurai jawaban JSON."
                    return
                }
                if httpResponse.statusCode >= 400 {
                    let errText = (json["error"] as? String) ?? "Terjadi kesalahan pada server model."
                    self.quickAskStatusLabel?.stringValue = "Gagal (\(httpResponse.statusCode))"
                    self.quickAskAnswerView?.string = errText
                    return
                }
                let reply = (json["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(Jawaban kosong)"
                let usedModel = (json["model"] as? String) ?? (self.selectedModelID ?? "Gemma Lokal")
                self.quickAskStatusLabel?.stringValue = "✓ Dijawab oleh \(usedModel)"
                self.quickAskAnswerView?.string = reply
                self.refreshMemoryStats()
            }
        }.resume()
    }

    @objc private func forwardQuickAskToWorkspace() {
        let prompt = quickAskInput?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        quickAskPanel?.orderOut(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if webContainer.isHidden {
            openSelectedView()
        }
        guard !prompt.isEmpty,
              let encoded = try? JSONSerialization.data(withJSONObject: [prompt], options: [.fragmentsAllowed]),
              let jsonArgs = String(data: encoded, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.webView?.evaluateJavaScript("""
            ((text) => {
                const input = document.querySelector('#user-input, #chat-input, #prompt-input, #message-input, textarea');
                if (input) {
                    input.value = text;
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.focus();
                    const sendBtn = document.querySelector('#send-btn, #send-button, #submit-btn, button[type="submit"]');
                    if (sendBtn && !sendBtn.disabled) sendBtn.click();
                }
            })(...\(jsonArgs));
            """, completionHandler: nil)
        }
    }

    @objc private func copyQuickAskAnswer() {
        guard let answer = quickAskAnswerView?.string, !answer.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(answer, forType: .string)
        quickAskStatusLabel?.stringValue = "✓ Jawaban disalin ke papan klip."
    }

    private func refreshMemoryStats() {
        guard let url = modelAPIURL(path: "/api/system/memory") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        modelSession.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.litertMemoryMB = (payload["litert_rss_mb"] as? NSNumber)?.doubleValue ?? 0
                self.backendMemoryMB = (payload["backend_rss_mb"] as? NSNumber)?.doubleValue ?? 0
                self.updateStatusItemModel()
            }
        }.resume()
    }

    @objc private func menuRefreshModelMemory() {
        startupStatus?.stringValue = "♻️ Menyegarkan memori model LiteRT-LM & WebView…"
        guard let url = modelAPIURL(path: "/api/system/restart-model-server") else { return }
        purgeInactiveWebViews()
        updateDockTileStatus(isGenerating: true, text: "♻️ RAM")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        modelSession.dataTask(with: request) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateDockTileStatus(isGenerating: false)
                self.refreshMemoryStats()
                self.startupStatus?.stringValue = "✓ Memori model LiteRT-LM telah disegarkan."
                NSSound.beep()
            }
        }.resume()
    }

    @objc private func openNativeLanQRPanel() {
        if lanQRPanel == nil {
            makeNativeLanQRPanel()
        }
        refreshNativeLanQRInfo()
        lanQRPanel?.center()
        lanQRPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeNativeLanQRPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Akses LAN HTTPS & QR Code"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .withinWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(calibratedRed: 0.095, green: 0.042, blue: 0.23, alpha: 0.96).cgColor
        bg.translatesAutoresizingMaskIntoConstraints = false

        let qrView = NSImageView()
        qrView.wantsLayer = true
        qrView.layer?.backgroundColor = NSColor.white.cgColor
        qrView.layer?.cornerRadius = 14
        qrView.imageScaling = .scaleProportionallyUpOrDown
        qrView.translatesAutoresizingMaskIntoConstraints = false
        self.lanQRImageView = qrView

        let heading = NSTextField(labelWithString: "Pindai QR untuk Buka dari Perangkat Lain")
        heading.font = .systemFont(ofSize: 16, weight: .bold)
        heading.textColor = .white

        let addrLabel = NSTextField(labelWithString: "Alamat IP Jaringan Lokal (Wi-Fi):")
        addrLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        addrLabel.textColor = NSColor(calibratedRed: 0.85, green: 0.80, blue: 0.98, alpha: 0.9)

        let picker = NSPopUpButton()
        picker.controlSize = .regular
        picker.target = self
        picker.action = #selector(lanQRAddressChanged(_:))
        self.lanQRAddressPicker = picker

        let urlField = NSTextField(labelWithString: baseURL?.absoluteString ?? "https://127.0.0.1:1234/utama.html")
        urlField.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        urlField.textColor = NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.86, alpha: 1)
        urlField.isSelectable = true
        self.lanQRURLField = urlField

        let copyBtn = NSButton(title: "Salin URL", target: self, action: #selector(copyLanQRURL))
        copyBtn.bezelStyle = .rounded
        let openBtn = NSButton(title: "Buka Browser", target: self, action: #selector(openLanQRInBrowser))
        openBtn.bezelStyle = .rounded
        let caBtn = NSButton(title: "Unduh Sertifikat CA (.cer)", target: self, action: #selector(downloadLanQRCACert))
        caBtn.bezelStyle = .rounded
        caBtn.bezelColor = NSColor(calibratedRed: 0.925, green: 0.282, blue: 0.600, alpha: 1.0)
        caBtn.contentTintColor = .white

        let status = NSTextField(labelWithString: "Gunakan HTTPS LAN agar Mikrofon & WebGPU berjalan di iPhone/iPad.")
        status.font = .systemFont(ofSize: 11)
        status.textColor = NSColor(calibratedRed: 0.80, green: 0.75, blue: 0.94, alpha: 0.85)
        self.lanQRStatusLabel = status

        let btnRow = NSStackView(views: [copyBtn, openBtn])
        btnRow.orientation = .horizontal
        btnRow.distribution = .fillEqually
        btnRow.spacing = 8

        let rightStack = NSStackView(views: [addrLabel, picker, urlField, btnRow, caBtn, status])
        rightStack.orientation = .vertical
        rightStack.alignment = .leading
        rightStack.spacing = 10

        let bodyRow = NSStackView(views: [qrView, rightStack])
        bodyRow.orientation = .horizontal
        bodyRow.alignment = .top
        bodyRow.spacing = 18

        let mainStack = NSStackView(views: [heading, bodyRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView?.addSubview(bg)
        panel.contentView?.addSubview(mainStack)
        if let cv = panel.contentView {
            NSLayoutConstraint.activate([
                bg.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                bg.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                bg.topAnchor.constraint(equalTo: cv.topAnchor),
                bg.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
                qrView.widthAnchor.constraint(equalToConstant: 200),
                qrView.heightAnchor.constraint(equalToConstant: 200),
                mainStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 22),
                mainStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -22),
                mainStack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
                mainStack.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -20),
            ])
        }
        lanQRPanel = panel
    }

    private func refreshNativeLanQRInfo() {
        let selectedIdx = max(0, viewPicker.indexOfSelectedItem)
        let activePath = appViews[min(selectedIdx, appViews.count - 1)].path
        let initialURL = baseURL?.appendingPathComponent(activePath).absoluteString ?? "https://127.0.0.1:1234/\(activePath)"
        updateNativeQRCode(urlString: initialURL)

        guard let infoURL = modelAPIURL(path: "/api/network-info") else { return }
        modelSession.dataTask(with: infoURL) { [weak self] data, response, _ in
            guard let self,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let addrs = json["addresses"] as? [String],
                  !addrs.isEmpty else { return }
            DispatchQueue.main.async {
                self.lanQRAddresses = addrs
                self.lanQRAddressPicker?.removeAllItems()
                self.lanQRAddressPicker?.addItems(withTitles: addrs)
                self.updateSelectedLanQRURL()
            }
        }.resume()
    }

    @objc private func lanQRAddressChanged(_ sender: NSPopUpButton) {
        updateSelectedLanQRURL()
    }

    private func updateSelectedLanQRURL() {
        let selectedIdx = max(0, viewPicker.indexOfSelectedItem)
        let activePath = appViews[min(selectedIdx, appViews.count - 1)].path
        let host = lanQRAddressPicker?.titleOfSelectedItem ?? lanQRAddresses.first ?? "127.0.0.1"
        let port = baseURL?.port ?? 1234
        let urlStr = "https://\(host):\(port)/\(activePath)"
        updateNativeQRCode(urlString: urlStr)
    }

    private func updateNativeQRCode(urlString: String) {
        lanQRURLField?.stringValue = urlString
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(Data(urlString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return }
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: transformed)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        lanQRImageView?.image = nsImage
    }

    @objc private func copyLanQRURL() {
        guard let str = lanQRURLField?.stringValue, !str.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        lanQRStatusLabel?.stringValue = "✓ Tautan HTTPS LAN berhasil disalin ke Clipboard!"
    }

    @objc private func openLanQRInBrowser() {
        guard let str = lanQRURLField?.stringValue, let url = URL(string: str) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func downloadLanQRCACert() {
        guard let caURL = modelAPIURL(path: "/api/lan-ca") else { return }
        modelSession.dataTask(with: caURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data else {
                    self.lanQRStatusLabel?.stringValue = "Sertifikat CA tidak tersedia saat ini."
                    return
                }
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "gemma-ai-gallery-lan-ca.cer"
                if let win = self.lanQRPanel {
                    panel.beginSheetModal(for: win) { resp in
                        if resp == .OK, let dest = panel.url {
                            try? data.write(to: dest, options: .atomic)
                            self.lanQRStatusLabel?.stringValue = "✓ Sertifikat CA disimpan."
                        }
                    }
                }
            }
        }.resume()
    }

    @objc private func menuPurgeInactiveWebViews() {
        purgeInactiveWebViews()
        updateStatusItemModel()
    }

    private func purgeInactiveWebViews() {
        var keysToRemove: [String] = []
        for (path, wv) in workspaceWebViews where wv != self.webView {
            wv.stopLoading()
            wv.removeFromSuperview()
            keysToRemove.append(path)
        }
        for key in keysToRemove {
            workspaceWebViews.removeValue(forKey: key)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminatingApp = true
        standaloneMode = false
        readinessTimer?.invalidate()
        memoryTimer?.invalidate()
        if let backendProcess, backendProcess.isRunning {
            backendProcess.terminate()
            backendProcess.waitUntilExit()
        }
        try? backendLogHandle?.close()
        backendLogHandle = nil
        terminalApplication?.unhide()
    }

    func windowWillClose(_ notification: Notification) {
        if isTerminatingApp {
            NSApp.terminate(nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let currentPath = webView.url?.lastPathComponent, !currentPath.isEmpty else { return }
        if webView == self.webView {
            syncAppearanceWithActiveWebView()
            if let matchedIndex = appViews.firstIndex(where: { $0.path == currentPath }) {
                let matchedView = appViews[matchedIndex]
                webTitle.stringValue = matchedView.title
                viewPicker.selectItem(at: matchedIndex)
                toolbarWorkspacePicker?.selectItem(at: matchedIndex)
                toolbarModelBadge?.stringValue = selectedModelID.map { "·  \($0)" } ?? ""
                updateStatusItemModel()
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Batal")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Batal")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input

        completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    @available(macOS 12.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    // MARK: - Hermes Autonomous Agent Hub & Self-Heal Panel
    private var hermesHubPanel: NSPanel?

    @objc func openHermesHubPanel() {
        if hermesHubPanel == nil {
            makeHermesHubPanel()
        }
        hermesHubPanel?.center()
        hermesHubPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeHermesHubPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "🧠 Hermes Autonomous Agent Hub & Self-Heal"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let glassBackground = NSVisualEffectView()
        glassBackground.material = .popover
        glassBackground.blendingMode = .behindWindow
        glassBackground.state = .active
        glassBackground.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Hermes Autonomous Agent Hub")
        header.font = .systemFont(ofSize: 14, weight: .bold)
        header.textColor = .labelColor

        let subheader = NSTextField(
            wrappingLabelWithString: "Manajemen subagent otonom, delegasi tugas (/api/hermes/delegate), dan mekanisme perbaikan mandiri kode & prompt (/api/hermes/self-heal)."
        )
        subheader.font = .systemFont(ofSize: 11.5)
        subheader.textColor = .secondaryLabelColor

        let container = NSView()
        container.addSubview(glassBackground)
        container.addSubview(header)
        container.addSubview(subheader)
        header.translatesAutoresizingMaskIntoConstraints = false
        subheader.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            glassBackground.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glassBackground.topAnchor.constraint(equalTo: container.topAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),

            subheader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            subheader.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            subheader.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
        ])

        panel.contentView = container
        self.hermesHubPanel = panel
    }
}

let application = NSApplication.shared
let delegate = WindowDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
