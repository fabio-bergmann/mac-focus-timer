import AppKit
import Combine
import FocusTimerCore

/// The menu bar item. A click opens the panel under it; a right-click offers
/// the few things worth reaching without the panel.
final class StatusItemController: NSObject {
    var onClick: (() -> Void)?
    var onShowSettings: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings: AppSettings
    private let timer: TimerController
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var drawn: Drawn?

    /// Everything the image depends on, to skip redraws that change nothing.
    private struct Drawn: Equatable {
        var content: PillContent
        var bar: NSColor
        var dark: Bool
    }

    init(settings: AppSettings, timer: TimerController) {
        self.settings = settings
        self.timer = timer
        super.init()

        item.autosaveName = "FocusTimer"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            // The menu bar turns light or dark with the wallpaper behind it.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.render() }
            }
        }

        // objectWillChange fires before the new value lands, so draw on the next turn.
        Publishers.Merge(timer.objectWillChange, settings.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &subscriptions)
        render()
    }

    private func render() {
        guard let button = item.button else { return }
        var content = PillContent.make(state: timer.state, now: Date(), style: settings.displayStyle)
        // Whole-pixel steps are all the bar can show.
        content.fraction = (content.fraction * 200).rounded() / 200
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let next = Drawn(content: content, bar: settings.barColor, dark: dark)
        guard next != drawn else { return }
        drawn = next

        button.image = PillRenderer.image(for: content, bar: next.bar, darkMenuBar: dark, devMarker: AppVariant.isDev)
        let description = accessibilityDescription
        button.toolTip = description
        button.setAccessibilityTitle(description)
    }

    private var accessibilityDescription: String {
        let state = timer.state
        switch state.phase {
        case .idle:
            return AppVariant.name
        case .running, .paused:
            let left = DurationFormat.spoken(Int((state.remaining(now: Date()) ?? 0).rounded(.up)))
            let label = state.label.map { "\($0): " } ?? ""
            return "\(label)\(left) left\(state.isPaused ? ", paused" : "")"
        case .finished:
            return state.label.map { "\($0): finished" } ?? "Timer finished"
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onClick?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        if timer.state.isActive {
            if timer.state.isPaused {
                menu.addItem(menuItem("Resume", #selector(resume)))
            } else {
                menu.addItem(menuItem("Pause", #selector(pause)))
            }
            menu.addItem(menuItem("Stop", #selector(stop)))
            menu.addItem(.separator())
        }
        menu.addItem(menuItem("Settings…", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit \(AppVariant.name)", #selector(quit)))

        // Attaching the menu only for this click keeps left-click free for the panel.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func pause() { timer.pause() }
    @objc private func resume() { timer.resume() }
    @objc private func stop() { timer.stop() }
    @objc private func showSettings() { onShowSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
