import UIKit

/// Swift mirror of TIODesign.h/.m for the caption panels, which live in separate
/// Swift modules. The tables below carry the same values as
/// docs/design-system/tokens.json and TIODesign.inc; tests/tio_design_swift.py
/// compares them with tokens.json. Use these tokens, never literal colors,
/// `systemFont(ofSize:)` or numeric padding.
enum TIODesign {
    enum Color: String, CaseIterable {
        case bg, label, separator, accent, focusRing = "focus-ring"
        case bgRaised = "bg-raised", bgSunken = "bg-sunken"
        case labelSecondary = "label-secondary", labelTertiary = "label-tertiary"
        case accentFill = "accent-fill", onAccent = "on-accent", accentSoft = "accent-soft"
        case tileAssistant = "tile-assistant", tileMedia = "tile-media", tileDeveloper = "tile-developer"
        case statusOk = "status-ok", statusWarn = "status-warn", statusDanger = "status-danger"
        case lensBlack = "lens-black", lensFull = "lens-full", lensHigh = "lens-high"
        case lensMid = "lens-mid", lensTrack = "lens-track", lensGuide = "lens-guide"
    }

    enum TextStyle: String, CaseIterable {
        case largeTitle = "large-title", title2, title3, headline, body, subheadline, footnote, caption
        var uiStyle: UIFont.TextStyle {
            switch self {
            case .largeTitle: return .largeTitle
            case .title2: return .title2
            case .title3: return .title3
            case .headline: return .headline
            case .body: return .body
            case .subheadline: return .subheadline
            case .footnote: return .footnote
            case .caption: return .caption1
            }
        }
    }

    // Token name: (light, dark) as 0xRRGGBB.
    static let colorTable: [String: (light: UInt32, dark: UInt32)] = [
        "bg": (0xf2f2f7, 0x17131b),
        "bg-raised": (0xffffff, 0x221d25),
        "bg-sunken": (0xe5e5ea, 0x2c2630),
        "label": (0x000000, 0xf0ede5),
        "label-secondary": (0x6c6c70, 0xa39fa8),
        "label-tertiary": (0x8a8a8e, 0x766f7c),
        "separator": (0xc6c6c8, 0x3a3340),
        "accent": (0x4d6c00, 0xdbf67a),
        "accent-fill": (0x4d6c00, 0xdbf67a),
        "on-accent": (0xffffff, 0x17131b),
        "accent-soft": (0xeef5d6, 0x2c3020),
        "tile-assistant": (0x5856d6, 0x5e5ce6),
        "tile-media": (0xd30f45, 0xff375f),
        "tile-developer": (0x636366, 0x8e8e93),
        "status-ok": (0x1e7b34, 0x30db5b),
        "status-warn": (0xb25000, 0xffb340),
        "status-danger": (0xd70015, 0xff6961),
        "focus-ring": (0x4d6c00, 0xdbf67a),
        "lens-black": (0x000000, 0x000000),
        "lens-full": (0x00ff00, 0x00ff00),
        "lens-high": (0x00b000, 0x00b000),
        "lens-mid": (0x007700, 0x007700),
        "lens-track": (0x003800, 0x003800),
        "lens-guide": (0xff7a1a, 0xff7a1a),
    ]

    // Token name: (point size at Large, CSS weight).
    static let typeTable: [String: (size: CGFloat, weight: Int)] = [
        "large-title": (34, 700),
        "title2": (22, 700),
        "title3": (20, 600),
        "headline": (17, 600),
        "body": (17, 400),
        "subheadline": (15, 400),
        "footnote": (13, 400),
        "caption": (12, 400),
    ]

    // Spacing, radius and size tokens in points.
    static let numberTable: [String: CGFloat] = [
        "space-1": 4,
        "space-2": 8,
        "space-3": 12,
        "space-4": 16,
        "space-5": 20,
        "space-6": 24,
        "space-8": 32,
        "radius-xs": 2,
        "radius-sm": 7,
        "radius-md": 12,
        "radius-lg": 26,
        "radius-pill": 999,
        "hit-min": 44,
        "icon-tile": 30,
        "button-height": 50,
    ]

    private static func rgb(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    /// Dynamic light/dark color; the lens-* tokens are identical in both.
    static func color(_ token: Color) -> UIColor {
        let row = colorTable[token.rawValue] ?? (0, 0)
        if row.light == row.dark { return rgb(row.light) }
        let light = row.light, dark = row.dark
        return UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) }
    }

    private static func weight(_ css: Int) -> UIFont.Weight {
        css >= 700 ? .bold : css >= 600 ? .semibold : css >= 500 ? .medium : .regular
    }

    /// Text styles only, scaled with UIFontMetrics. Set adjustsFontForContentSizeCategory.
    static func font(_ style: TextStyle, weight override: UIFont.Weight? = nil) -> UIFont {
        let row = typeTable[style.rawValue] ?? (17, 400)
        let base = UIFont.systemFont(ofSize: row.size, weight: override ?? weight(row.weight))
        return UIFontMetrics(forTextStyle: style.uiStyle).scaledFont(for: base)
    }

    static func number(_ name: String) -> CGFloat { numberTable[name] ?? 0 }
    static var space1: CGFloat { number("space-1") }
    static var space2: CGFloat { number("space-2") }
    static var space3: CGFloat { number("space-3") }
    static var space4: CGFloat { number("space-4") }
    static var space6: CGFloat { number("space-6") }
    static var radiusMD: CGFloat { number("radius-md") }
    static var hitMin: CGFloat { number("hit-min") }

    /// List row on bg-raised: body title, subheadline label-secondary subtitle.
    @MainActor static func styleRow(_ cell: UITableViewCell) {
        cell.backgroundColor = color(.bgRaised)
        cell.textLabel?.textColor = color(.label)
        cell.textLabel?.font = font(.body)
        cell.detailTextLabel?.textColor = color(.labelSecondary)
        cell.detailTextLabel?.font = font(.subheadline)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.tintColor = color(.accent)
        cell.imageView?.tintColor = color(.accent)
        cell.contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: space3, leading: space4, bottom: space3, trailing: space4)
        let selected = UIView()
        selected.backgroundColor = color(.accentSoft)
        cell.selectedBackgroundView = selected
    }

    /// Read-only text inside a row: body, label, no fill.
    @MainActor static func styleReadOnlyText(_ view: UITextView) {
        view.font = font(.body)
        view.textColor = color(.label)
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = true
    }

    /// Inset-grouped table surface. The hub shell already installs the per-table
    /// header and cell proxy, so this sets only the table's own colors.
    @MainActor static func styleTable(_ table: UITableView) {
        table.backgroundColor = color(.bg)
        table.tintColor = color(.accent)
        table.separatorColor = color(.separator)
        table.estimatedRowHeight = 56
        table.cellLayoutMarginsFollowReadableWidth = true
    }
}
