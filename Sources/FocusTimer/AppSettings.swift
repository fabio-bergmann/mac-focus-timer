import AppKit
import Combine
import FocusTimerCore
import ServiceManagement

/// Which build this is. `scripts/dev.sh` runs a second copy beside the
/// installed app, told apart by its bundle id.
enum AppVariant {
    static let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    static let name = isDev ? "Focus Timer Dev" : "Focus Timer"
    /// The dev build takes another shortcut, or the two would fight over one.
    static let defaultHotKey: KeyCombo = isDev ? .controlOptionSpace : .optionSpace
}

final class AppSettings: ObservableObject {
    static let defaultPresets = ["5m", "15m", "30m", "45m", "1h", "1h 30m"]
    static let defaultBarColorHex = "#A855F7"
    static let palette = [
        "#A855F7", "#6366F1", "#3B82F6", "#14B8A6", "#22C55E",
        "#EAB308", "#F97316", "#EF4444", "#EC4899", "#FFFFFF",
    ]

    /// Each preset is typed the same way as a query: "25m", "1h 30m Deep work".
    @Published var presets: [String] { didSet { defaults.set(presets, forKey: Key.presets) } }
    @Published var barColorHex: String { didSet { defaults.set(barColorHex, forKey: Key.barColor) } }
    @Published var barOpacity: Double { didSet { defaults.set(barOpacity, forKey: Key.barOpacity) } }
    @Published var displayStyle: DisplayStyle { didSet { defaults.set(displayStyle.rawValue, forKey: Key.displayStyle) } }
    @Published var pillFontWeight: PillFontWeight { didSet { defaults.set(pillFontWeight.rawValue, forKey: Key.fontWeight) } }
    /// Off lets the menu bar item grow and shrink with the time it shows.
    @Published var pillWidthIsFixed: Bool { didSet { defaults.set(pillWidthIsFixed, forKey: Key.widthIsFixed) } }
    @Published var pillFixedWidth: Double { didSet { defaults.set(pillFixedWidth, forKey: Key.fixedWidth) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.sound) } }
    /// The glow around the screen when a timer ends.
    @Published var glowEnabled: Bool { didSet { defaults.set(glowEnabled, forKey: Key.glow) } }
    @Published var hotKey: KeyCombo { didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: Key.hotKey) } }

    /// True while Settings waits for a new shortcut.
    @Published var isRecordingShortcut = false
    /// The system refused the shortcut.
    @Published var hotKeyUnavailable = false

    private let defaults: UserDefaults

    private enum Key {
        static let presets = "presets"
        static let barColor = "barColor"
        static let barOpacity = "barOpacity"
        static let displayStyle = "displayStyle"
        static let fontWeight = "pillFontWeight"
        static let widthIsFixed = "pillWidthIsFixed"
        static let fixedWidth = "pillFixedWidth"
        static let sound = "soundEnabled"
        static let glow = "glowEnabled"
        static let hotKey = "hotKey"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = defaults.stringArray(forKey: Key.presets) ?? Self.defaultPresets
        barColorHex = defaults.string(forKey: Key.barColor) ?? Self.defaultBarColorHex
        barOpacity = defaults.object(forKey: Key.barOpacity) as? Double ?? 0.55
        displayStyle = defaults.string(forKey: Key.displayStyle).flatMap(DisplayStyle.init) ?? .compact
        pillFontWeight = defaults.string(forKey: Key.fontWeight).flatMap(PillFontWeight.init) ?? .regular
        pillWidthIsFixed = defaults.object(forKey: Key.widthIsFixed) as? Bool ?? true
        pillFixedWidth = defaults.object(forKey: Key.fixedWidth) as? Double ?? PillWidth.defaultFixed
        soundEnabled = defaults.object(forKey: Key.sound) as? Bool ?? true
        glowEnabled = defaults.object(forKey: Key.glow) as? Bool ?? true
        hotKey = defaults.data(forKey: Key.hotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? AppVariant.defaultHotKey
    }

    /// The bar behind the time, with its transparency.
    var barColor: NSColor {
        NSColor(hex: barColorHex, alpha: barOpacity) ?? NSColor(hex: Self.defaultBarColorHex, alpha: barOpacity)!
    }

    /// Everything about the menu bar item's look that is set here.
    var pillStyle: PillStyle {
        PillStyle(
            bar: barColor, weight: pillFontWeight,
            width: pillWidthIsFixed ? .fixed(pillFixedWidth) : .automatic
        )
    }
}

extension NSColor {
    convenience init?(hex: String, alpha: Double = 1) {
        guard let rgb = RGB(hex: hex) else { return nil }
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}

/// "Open at login", which only exists for the installed bundle.
enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        isAvailable && SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
