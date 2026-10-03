import AppKit
import SwiftUI

/// The floating panel. It takes the keyboard without activating the app, so
/// whatever was in front stays in front once it closes.
final class LauncherPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onToggleSettings: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    // An accessory app has no menu bar, so nothing maps the Edit shortcuts to
    // the text fields unless the panel does it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown, flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case ",":
                onToggleSettings?()
                return true
            case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            case "z": return NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 520, height: 420)
    static let cornerRadius: CGFloat = 16

    private let panel: LauncherPanel
    private let model: LauncherModel
    private var clickMonitor: Any?
    private var lastDismissal = Date.distantPast

    init(model: LauncherModel) {
        self.model = model
        panel = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.delegate = self

        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        let host = NSHostingView(rootView: PanelRootView(model: model))
        host.frame = backdrop.bounds
        host.autoresizingMask = [.width, .height]
        backdrop.addSubview(host)
        panel.contentView = backdrop

        panel.onEscape = { [weak model] in model?.escape() }
        panel.onToggleSettings = { [weak model] in model?.toggleSettings() }
        model.dismiss = { [weak self] in self?.hide() }
    }

    /// - Parameter fromMenuBar: the request is a click on the menu bar item.
    func toggle(fromMenuBar: Bool = false) {
        if panel.isVisible {
            hide()
            return
        }
        // Clicking the menu bar item to close the panel can dismiss it on
        // mouse-down and then arrive here on mouse-up; don't reopen for that.
        if fromMenuBar, Date().timeIntervalSince(lastDismissal) < 0.4 { return }
        show()
    }

    /// Opens in the same spot however it was asked for: the shortcut and a
    /// click on the menu bar item both land in the middle of the screen.
    func show(settings: Bool = false) {
        model.prepareForShow(mode: settings ? .settings : .launcher)
        panel.setFrame(centeredFrame(), display: true)
        panel.makeKeyAndOrderFront(nil)

        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.hide()
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastDismissal = Date()
        model.settings.isRecordingShortcut = false
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func centeredFrame() -> NSRect {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: Self.size)
        return NSRect(
            x: visible.midX - Self.size.width / 2,
            y: visible.maxY - visible.height * 0.18 - Self.size.height,
            width: Self.size.width, height: Self.size.height
        )
    }

    /// A stretchable mask, which rounds the blur and the window shadow together.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
