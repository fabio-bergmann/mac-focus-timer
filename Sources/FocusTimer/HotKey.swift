import AppKit
import Carbon.HIToolbox

/// A global shortcut: a virtual key plus Carbon modifier flags, and how to show it.
struct KeyCombo: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let optionSpace = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), display: "⌥Space")
}

extension KeyCombo {
    /// Reads a combo from a key press. Nil unless ⌘, ⌥ or ⌃ is held: a global
    /// shortcut on a plain key would eat ordinary typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.subtracting(.shift).isEmpty, let name = Self.keyName(for: event) else { return nil }

        var modifiers: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); symbols += "⌘" }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, display: symbols + name)
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(for event: NSEvent) -> String? {
        if let name = namedKeys[Int(event.keyCode)] { return name }
        guard let characters = event.charactersIgnoringModifiers?.uppercased(), !characters.isEmpty else { return nil }
        return characters
    }
}

/// Registers one system-wide shortcut through Carbon, which needs no
/// Accessibility permission.
final class HotKey {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onPress?()
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Swaps the registered shortcut; nil releases it. False when the system
    /// refuses the combination.
    @discardableResult
    func register(_ combo: KeyCombo?) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let combo else { return true }
        let identifier = EventHotKeyID(signature: OSType(0x4654_4D52), id: 1) // 'FTMR'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }
}
