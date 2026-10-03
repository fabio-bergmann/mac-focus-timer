import AppKit
import Combine
import FocusTimerCore
import ServiceManagement

final class AppSettings: ObservableObject {
    static let defaultPresets = ["5m", "15m", "25m", "30m", "45m", "1h", "1h 30m", "2h"]
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
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.sound) } }
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
        static let sound = "soundEnabled"
        static let hotKey = "hotKey"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = defaults.stringArray(forKey: Key.presets) ?? Self.defaultPresets
        barColorHex = defaults.string(forKey: Key.barColor) ?? Self.defaultBarColorHex
        barOpacity = defaults.object(forKey: Key.barOpacity) as? Double ?? 0.55
        displayStyle = defaults.string(forKey: Key.displayStyle).flatMap(DisplayStyle.init) ?? .compact
        soundEnabled = defaults.object(forKey: Key.sound) as? Bool ?? true
        hotKey = defaults.data(forKey: Key.hotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .optionSpace
    }

    /// The bar behind the time, with its transparency.
    var barColor: NSColor {
        NSColor(hex: barColorHex, alpha: barOpacity) ?? NSColor(hex: Self.defaultBarColorHex, alpha: barOpacity)!
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
