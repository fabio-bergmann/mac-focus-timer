import AppKit
import Combine
import FocusTimerCore

/// The menu bar item. A click opens the panel; pulling the item down onto the
/// screen sets a timer as long as the pull; a right-click offers the few
/// things worth reaching without the panel.
final class StatusItemController: NSObject {
    var onClick: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onDragStart: (() -> Void)?
    var willStartTimer: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings: AppSettings
    private let timer: TimerController
    private let overlay = DragTimerOverlay()
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var pressMonitor: Any?
    private var press: Press?
    private var drawn: Drawn?

    /// A left press on the item, from the mouse-down until the button is up.
    private struct Press {
        let start: NSPoint
        /// The item on screen, when the press could tell.
        let item: NSRect?
        let follower: Timer
        var isDrag = false
        /// Where the pull was last drawn, and in which steps.
        var pointer: NSPoint?
        var step = 1
        var seconds: Int?
    }

    /// How far the pointer moves before a press is a pull rather than a click.
    private static let dragThreshold: CGFloat = 4

    /// Everything the image depends on, to skip redraws that change nothing.
    private struct Drawn: Equatable {
        var content: PillContent
        var style: PillStyle
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
        // A left press is taken before the button sees it, since the button
        // would only ever report a click. Control and Command pass through:
        // Control-click is the menu, Command-drag moves the item.
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            // The drags and the mouse-up of a press are the press's.
            if press != nil { return nil }
            guard event.type == .leftMouseDown, let window = item.button?.window, event.window === window,
                  event.modifierFlags.isDisjoint(with: [.control, .command]) else { return event }
            beginPress(itemFrame: itemFrame)
            return nil
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
        let next = Drawn(content: content, style: settings.pillStyle, dark: dark)
        guard next != drawn else { return }
        drawn = next

        button.image = PillRenderer.image(for: content, style: next.style, darkMenuBar: dark, devMarker: AppVariant.isDev)
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

    // MARK: - Pressing and pulling

    /// The item's frame on screen, while its window knows where it is: the
    /// press can't tell, since it arrives at the middle of that window
    /// whichever spot was pressed, and the window's frame has been reported
    /// empty, so it only counts when it holds the pointer.
    private var itemFrame: NSRect? {
        guard let button = item.button, let window = button.window,
              window.frame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.isEmpty ? nil : frame
    }

    private func beginPress(itemFrame: NSRect?) {
        // The pointer and the button are read on a timer rather than from the
        // drag events. The press reaches the app through the menu bar, which
        // this macOS draws in another process, so nothing promises the events
        // that follow arrive the same way; and a press that missed its
        // mouse-up would leave the overlay stuck on screen.
        let follower = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] _ in self?.followPress() }
        RunLoop.main.add(follower, forMode: .common)
        press = Press(start: NSEvent.mouseLocation, item: itemFrame, follower: follower)
        item.button?.highlight(true)
    }

    private func followPress() {
        guard var press else { return }
        let pointer = NSEvent.mouseLocation
        if !press.isDrag, hypot(pointer.x - press.start.x, pointer.y - press.start.y) > Self.dragThreshold {
            press.isDrag = true
            onDragStart?()
            overlay.begin(at: press.start, item: press.item, bar: settings.barColor)
        }
        // Command, held once the press has begun, snaps to quarter hours.
        // Held from the start, the press is the system's, to move the item.
        let step = NSEvent.modifierFlags.contains(.command) ? DragDial.coarseStep : 1
        if press.isDrag, pointer != press.pointer || step != press.step {
            press.pointer = pointer
            press.step = step
            let seconds = overlay.follow(pointer, step: step, now: Date())
            // A tick on a Force Touch trackpad for each step of the dial.
            if seconds != press.seconds, seconds != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            press.seconds = seconds
        }
        self.press = press
        if NSEvent.pressedMouseButtons & 1 == 0 { endPress() }
    }

    private func endPress() {
        guard let press else { return }
        self.press = nil
        press.follower.invalidate()
        item.button?.highlight(false)
        guard press.isDrag else {
            onClick?()
            return
        }
        overlay.end()
        // Letting go back at the menu bar sets nothing.
        guard let seconds = press.seconds else { return }
        willStartTimer?()
        timer.start(seconds: seconds, label: nil)
    }

    // MARK: - Clicks and the menu

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
