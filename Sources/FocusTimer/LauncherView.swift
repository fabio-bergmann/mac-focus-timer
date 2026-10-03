import AppKit
import FocusTimerCore
import SwiftUI

struct PanelRootView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        Group {
            switch model.mode {
            case .launcher:
                LauncherView(model: model, timer: model.timer, settings: model.settings)
            case .settings:
                SettingsView(model: model, settings: model.settings, updates: model.updates)
            }
        }
        .frame(width: PanelController.size.width, height: PanelController.size.height)
        .background(
            RoundedRectangle(cornerRadius: PanelController.cornerRadius)
                .fill(Color(nsColor: .panelTint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelController.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.12))
        )
    }
}

extension NSColor {
    /// Laid over the blur so the glass reads as #F7F7F7 in light mode, where
    /// the bare material turns grey over dark windows. Dark mode keeps the
    /// material as it is.
    static let panelTint = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .clear
            : NSColor(srgbRed: 247 / 255, green: 247 / 255, blue: 247 / 255, alpha: 0.75)
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var timer: TimerController
    @ObservedObject var settings: AppSettings

    var body: some View {
        // Refreshes the "ends 15:42" times while the panel sits open.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = max(context.date, timer.now)
            let rows = model.rows(now: now)
            let selected = model.selected(in: rows)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                    QueryField(
                        text: $model.query,
                        placeholder: "25m, 1h30, until 15:30…",
                        focusToken: model.focusToken,
                        onMove: model.moveSelection(by:),
                        onSubmit: model.activateSelected,
                        onCancel: model.escape
                    )
                }
                .padding(.horizontal, 18)
                .frame(height: 56)

                Divider()
                if timer.state.isActive {
                    TimerStrip(state: timer.state, now: now, bar: Color(nsColor: settings.barColor))
                    Divider()
                }
                results(rows, selected: selected)
                Divider()
                footer(selected)
            }
        }
    }

    @ViewBuilder
    private func results(_ rows: [LauncherRow], selected: LauncherRow?) -> some View {
        if rows.isEmpty {
            VStack(spacing: 6) {
                Text("No timer in that yet")
                    .font(.system(size: 14, weight: .medium))
                Text("Try 25m, 1h30, 90s, 1:30:00 or until 15:30")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(rows) { row in
                            RowView(row: row, isSelected: row.id == selected?.id)
                                .id(row.id)
                                .onContinuousHover { phase in
                                    if case .active = phase { model.pointerMoved(over: row) }
                                }
                                .onTapGesture { model.activate(row) }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func footer(_ selected: LauncherRow?) -> some View {
        HStack(spacing: 8) {
            Button(action: model.toggleSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                    KeyCap("⌘,")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if let selected {
                Text(verb(for: selected.action))
                KeyCap("↩")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func verb(for action: LauncherAction) -> String {
        switch action {
        case .start: "Start"
        case .add: "Add time"
        case .pause: "Pause"
        case .resume: "Resume"
        case .stop: "Stop"
        }
    }
}

private struct RowView: View {
    let row: LauncherRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(row.title)
                .font(.system(size: 14, weight: .medium))
            if let subtitle = row.subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing = row.trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.1 : 0))
        )
        .contentShape(Rectangle())
    }
}

/// The running timer, shown above the list: the menu bar item at full size.
/// Same outline, same bar behind the text in the colour and opacity chosen in
/// Settings, draining the same way.
private struct TimerStrip: View {
    let state: TimerState
    let now: Date
    /// The bar colour, opacity included.
    let bar: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        // Paused dims everything, as it does in the menu bar.
        let strength: Double = state.isPaused ? 0.5 : 1

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DurationFormat.menuBar(state.remaining(now: now) ?? 0, style: .precise))
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
            Group {
                Text(state.isPaused ? "paused" : "left")
                if let label = state.label {
                    Text("· \(label)")
                        .lineLimit(1)
                }
                Spacer()
                if let end = state.endDate {
                    Text("ends \(end.formatted(date: .omitted, time: .shortened))")
                        .monospacedDigit()
                }
            }
            .opacity(0.7)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.primary.opacity(strength))
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(alignment: .leading) {
            GeometryReader { geometry in
                Rectangle()
                    .fill(bar.opacity(state.isPaused ? 0.6 : 1))
                    .frame(width: geometry.size.width * state.fraction(now: now))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.9 * strength), lineWidth: 1.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct KeyCap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

/// The query field. An AppKit field rather than a SwiftUI one because the
/// panel needs it focused the instant it opens, and needs the arrow keys,
/// Return and Escape while it keeps the keyboard.
struct QueryField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 21)
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QueryField
        var focusToken = -1

        init(_ parent: QueryField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }
}
