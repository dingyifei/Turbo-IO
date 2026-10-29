import UIKit

/// Shared chrome for the two live-caption panels (docs/design-system/screens/Captions.dc.html):
/// status pills, the bilingual transcript card and the Start/Stop button. Both panels hold a
/// `CaptionHeaderView` as their table header and pin a `CaptionActionFooter` to the bottom
/// safe area (the board's bottom button), so Stop stays reachable however far the transcript scrolls.
/// Colors, fonts and metrics come from TIODesign only.

/// Compact status pill: optional dot plus one short word or phrase. The dot is hidden from
/// VoiceOver; the text carries the meaning.
@MainActor final class CaptionPill: UIView {
    enum Kind { case ok, warn, neutral }
    private let dot = UIView(), label = UILabel()
    private let row = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = TIODesign.color(.bgRaised)
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.isAccessibilityElement = false
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8)])
        label.numberOfLines = 0
        label.font = TIODesign.font(.subheadline)
        label.adjustsFontForContentSizeCategory = true
        row.axis = .horizontal; row.alignment = .top; row.spacing = 6
        let dotSlot = UIView(); dotSlot.translatesAutoresizingMaskIntoConstraints = false; dotSlot.isAccessibilityElement = false
        dotSlot.addSubview(dot)
        NSLayoutConstraint.activate([dot.topAnchor.constraint(equalTo: dotSlot.topAnchor, constant: 7), dot.leadingAnchor.constraint(equalTo: dotSlot.leadingAnchor), dot.trailingAnchor.constraint(equalTo: dotSlot.trailingAnchor), dot.bottomAnchor.constraint(lessThanOrEqualTo: dotSlot.bottomAnchor)])
        row.addArrangedSubview(dotSlot); row.addArrangedSubview(label)
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Width of the pill if its text stays on one line.
    var naturalWidth: CGFloat { ceil(((label.text ?? "") as NSString).size(withAttributes: [.font: label.font as Any]).width) + 22 + (dot.superview?.isHidden == false ? 14 : 0) }

    func set(_ text: String, kind: Kind) {
        label.text = text
        accessibilityLabel = text
        switch kind {
        case .ok: label.textColor = TIODesign.color(.statusOk); dot.backgroundColor = TIODesign.color(.statusOk); dot.isHidden = false
        case .warn: label.textColor = TIODesign.color(.statusWarn); dot.backgroundColor = TIODesign.color(.statusWarn); dot.isHidden = false
        case .neutral: label.textColor = TIODesign.color(.labelSecondary); dot.isHidden = true
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.height / 2, TIODesign.number("radius-lg"))
    }
}

/// Table header: two pills above the transcript card (source language, rule, target language).
@MainActor final class CaptionHeaderView: UIView {
    let statusPill = CaptionPill(), privacyPill = CaptionPill()
    private let pills = UIStackView()
    private let card = UIView(), divider = UIView()
    private let sourceTitle = UILabel(), targetTitle = UILabel()
    private let sourceView = UITextView(), targetView = UITextView()
    private var sourceHeight: NSLayoutConstraint!, targetHeight: NSLayoutConstraint!
    private var targetGroup: [UIView] = []
    private var placeholders = (source: "", target: "")
    private var sourceText = "", targetText = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: TIODesign.space2, leading: TIODesign.space4, bottom: TIODesign.space3, trailing: TIODesign.space4)
        pills.axis = .horizontal; pills.spacing = TIODesign.space2; pills.alignment = .leading; pills.distribution = .fill
        pills.addArrangedSubview(statusPill); pills.addArrangedSubview(privacyPill)
        pills.isLayoutMarginsRelativeArrangement = true
        pills.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: TIODesign.space1, bottom: 0, trailing: TIODesign.space1)

        card.backgroundColor = TIODesign.color(.bgRaised)
        card.layer.cornerRadius = TIODesign.number("radius-lg")
        divider.backgroundColor = TIODesign.color(.separator)
        for title in [sourceTitle, targetTitle] {
            title.font = TIODesign.font(.caption); title.textColor = TIODesign.color(.labelSecondary)
            title.adjustsFontForContentSizeCategory = true
            title.isAccessibilityElement = false
        }
        for view in [sourceView, targetView] {
            view.isEditable = false; view.isSelectable = false
            view.backgroundColor = .clear
            view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
            view.adjustsFontForContentSizeCategory = true
            view.isScrollEnabled = true; view.showsVerticalScrollIndicator = false
            view.accessibilityTraits = .updatesFrequently
        }
        sourceView.font = TIODesign.font(.body)
        targetView.font = TIODesign.font(.title3)

        let inner = UIStackView(arrangedSubviews: [sourceTitle, sourceView, divider, targetTitle, targetView])
        inner.axis = .vertical; inner.spacing = TIODesign.space3 - 2
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        targetGroup = [divider, targetTitle, targetView]
        sourceHeight = sourceView.heightAnchor.constraint(equalToConstant: 24)
        targetHeight = targetView.heightAnchor.constraint(equalToConstant: 28)
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: TIODesign.space4),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -TIODesign.space4),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: TIODesign.space4),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -TIODesign.space4),
            sourceHeight, targetHeight,
        ])
        let outer = UIStackView(arrangedSubviews: [pills, card])
        outer.axis = .vertical; outer.spacing = TIODesign.space3; outer.alignment = .fill
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            outer.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            outer.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: CaptionHeaderView, _) in
            self.applyAxis(); self.refreshText()
        }
        applyAxis()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let before = pills.axis
        applyAxis()
        if pills.axis != before { setNeedsLayout() }
    }

    /// Pills sit side by side when both fit on one line and stack otherwise (larger text, ZH/EN expansion).
    private func applyAxis() {
        let available = (bounds.width > 0 ? bounds.width : 390) - layoutMargins.left - layoutMargins.right - 2 * TIODesign.space1
        let need = statusPill.naturalWidth + privacyPill.naturalWidth + TIODesign.space2
        let large = traitCollection.preferredContentSizeCategory >= .extraExtraLarge || need > available
        pills.axis = large ? .vertical : .horizontal
        pills.alignment = large ? .leading : .center
    }

    func configure(sourceName: String, targetName: String?, sourcePlaceholder: String, targetPlaceholder: String) {
        sourceTitle.text = sourceName; sourceView.accessibilityLabel = sourceName
        targetTitle.text = targetName; targetView.accessibilityLabel = targetName
        targetGroup.forEach { $0.isHidden = targetName == nil }
        placeholders = (sourcePlaceholder, targetPlaceholder)
        refreshText()
    }

    func setText(source: String, target: String) {
        sourceText = source; targetText = target
        refreshText()
    }

    private func refreshText() {
        show(sourceText, placeholder: placeholders.source, in: sourceView, height: sourceHeight)
        show(targetText, placeholder: placeholders.target, in: targetView, height: targetHeight)
    }

    private func show(_ text: String, placeholder: String, in view: UITextView, height: NSLayoutConstraint) {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        view.text = empty ? placeholder : text
        view.textColor = empty ? TIODesign.color(.labelTertiary) : TIODesign.color(.label)
        // Grow with the text up to three lines, then scroll to the newest words.
        let font = view.font ?? TIODesign.font(.body)
        let width = max(view.bounds.width > 0 ? view.bounds.width : (bounds.width > 0 ? bounds.width : 390) - 2 * (TIODesign.space4 + TIODesign.space4), 120)
        let fit = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let wanted = min(max(fit, ceil(font.lineHeight)), ceil(font.lineHeight) * 3)
        if abs(height.constant - wanted) > 0.5 { height.constant = wanted }
        if fit > wanted { view.setContentOffset(CGPoint(x: 0, y: max(0, view.contentSize.height - wanted)), animated: false) }
    }
}

/// Bottom bar holding the Start/Stop button (50 pt capsule) on a system material with a hairline above it.
/// `CaptionChrome.fit(_, in:, footer: true)` pins it to the table's bottom safe area.
@MainActor final class CaptionActionFooter: UIView {
    let button = UIButton(type: .system)
    private var title = "", prominent = true
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial)), hairline = UIView()
    private var bottomPadding: NSLayoutConstraint?
    /// Height the bar needs below the button for the home indicator.
    var safeBottom: CGFloat = 0 { didSet { bottomPadding?.constant = -(TIODesign.space3 + safeBottom) } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        material.translatesAutoresizingMaskIntoConstraints = false; material.isUserInteractionEnabled = false
        hairline.translatesAutoresizingMaskIntoConstraints = false; hairline.backgroundColor = TIODesign.color(.separator)
        addSubview(material); addSubview(hairline)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        let minimum = button.heightAnchor.constraint(greaterThanOrEqualToConstant: TIODesign.number("button-height"))
        let bottom = button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -TIODesign.space3)
        bottomPadding = bottom
        NSLayoutConstraint.activate([
            material.topAnchor.constraint(equalTo: topAnchor), material.bottomAnchor.constraint(equalTo: bottomAnchor),
            material.leadingAnchor.constraint(equalTo: leadingAnchor), material.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.topAnchor.constraint(equalTo: topAnchor), hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor), hairline.heightAnchor.constraint(equalToConstant: 1 / (traitCollection.displayScale > 0 ? traitCollection.displayScale : 3)),
            button.topAnchor.constraint(equalTo: topAnchor, constant: TIODesign.space3),
            bottom,
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TIODesign.space4),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TIODesign.space4),
            minimum,
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: CaptionActionFooter, _) in self.apply() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `prominent` is the accent-filled Start; Stop is the soft accent capsule.
    func set(title: String, prominent: Bool, enabled: Bool) {
        self.title = title; self.prominent = prominent
        button.isEnabled = enabled
        apply()
    }

    private func apply() {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = TIODesign.color(prominent ? .accentFill : .accentSoft)
        configuration.baseForegroundColor = TIODesign.color(prominent ? .onAccent : .accent)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: TIODesign.space3, leading: TIODesign.space4, bottom: TIODesign.space3, trailing: TIODesign.space4)
        var attributes = AttributeContainer()
        attributes.font = TIODesign.font(.headline)
        configuration.attributedTitle = AttributedString(title, attributes: attributes)
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 0
        button.accessibilityLabel = title
    }
}

enum CaptionChrome {
    /// Sizes a table header/footer view to the table width and reassigns it only when the
    /// height changes, so streaming text does not relayout the table on every update.
    @MainActor static func fit(_ view: UIView, in table: UITableView, footer: Bool = false) {
        let width = table.bounds.width
        guard width > 0 else { return }
        if footer, let bar = view as? CaptionActionFooter { pin(bar, in: table); return }
        let height = view.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                  withHorizontalFittingPriority: .required,
                                                  verticalFittingPriority: .fittingSizeLevel).height
        if abs(view.frame.height - height) < 0.5, abs(view.frame.width - width) < 0.5 { return }
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        if footer { table.tableFooterView = view } else { table.tableHeaderView = view }
    }

    /// Pins the action bar to the bottom safe area of a table (the table scrolls under it): the bar is a subview that follows
    /// the content offset, and the table's bottom inset equals the bar's height so the last row can scroll clear of it.
    @MainActor static func pin(_ bar: CaptionActionFooter, in table: UITableView) {
        let width = table.bounds.width
        guard width > 0 else { return }
        if bar.superview !== table { table.addSubview(bar) }
        let safe = table.safeAreaInsets.bottom
        if abs(bar.safeBottom - safe) > 0.5 { bar.safeBottom = safe }
        bar.frame.size.width = width
        let height = bar.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                 withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let inset = max(0, height - safe)
        if abs(table.contentInset.bottom - inset) > 0.5 {
            table.contentInset.bottom = inset
            table.verticalScrollIndicatorInsets.bottom = inset
        }
        bar.frame = CGRect(x: 0, y: table.contentOffset.y + table.bounds.height - height, width: width, height: height)
        table.bringSubviewToFront(bar)
    }

    /// Keeps a pinned bar at the bottom while the table scrolls.
    @MainActor static func follow(_ bar: CaptionActionFooter, in table: UITableView) {
        guard bar.superview === table, bar.frame.height > 0 else { return }
        bar.frame.origin.y = table.contentOffset.y + table.bounds.height - bar.frame.height
    }
}
