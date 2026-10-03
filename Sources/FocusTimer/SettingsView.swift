import AppKit
import Carbon.HIToolbox
import FocusTimerCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates: UpdateService

    @State private var newPreset = ""
    @State private var hexDraft = ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                HStack {
                    Button(action: model.showLauncher) {
                        HStack(spacing: 4) {
                            IconView(.chevronLeft, size: 14)
                            Text("Timers")
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer()
                    Button("Quit \(AppVariant.name)") { NSApp.terminate(nil) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    presetsSection
                    menuBarSection
                    shortcutSection
                    generalSection
                    updatesSection
                }
                .padding(18)
            }
        }
        .onAppear { hexDraft = settings.barColorHex }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Presets

    private var presetsSection: some View {
        section("Presets") {
            ForEach(Array(settings.presets.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 8) {
                    TextField("25m", text: presetBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                    Text(summary(of: preset(at: index)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    iconButton(.chevronUp, help: "Move up") { movePreset(index, by: -1) }
                        .disabled(index == 0)
                    iconButton(.chevronDown, help: "Move down") { movePreset(index, by: 1) }
                        .disabled(index == settings.presets.count - 1)
                    iconButton(.cancel, help: "Remove") { removePreset(index) }
                }
            }
            HStack(spacing: 8) {
                TextField("Add a preset: 45m, 1h30 Deep work, until 17:00", text: $newPreset)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPreset)
                Button("Add", action: addPreset)
                    .disabled(DurationParser.parse(newPreset) == nil)
            }
        }
    }

    private func preset(at index: Int) -> String {
        settings.presets.indices.contains(index) ? settings.presets[index] : ""
    }

    private func presetBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { preset(at: index) },
            set: { if settings.presets.indices.contains(index) { settings.presets[index] = $0 } }
        )
    }

    private func summary(of preset: String) -> String {
        guard let timer = DurationParser.parse(preset) else { return "Not a time, so it's skipped" }
        let length = DurationFormat.spoken(timer.seconds)
        let time = timer.endsAt.map { "until \($0.formatted(date: .omitted, time: .shortened))" } ?? length
        return [time, timer.label].compactMap { $0 }.joined(separator: " · ")
    }

    private func movePreset(_ index: Int, by delta: Int) {
        let target = index + delta
        guard settings.presets.indices.contains(index), settings.presets.indices.contains(target) else { return }
        settings.presets.swapAt(index, target)
    }

    private func removePreset(_ index: Int) {
        guard settings.presets.indices.contains(index) else { return }
        settings.presets.remove(at: index)
    }

    private func addPreset() {
        let preset = newPreset.trimmingCharacters(in: .whitespaces)
        guard DurationParser.parse(preset) != nil else { return }
        settings.presets.append(preset)
        newPreset = ""
    }

    private func iconButton(_ icon: Icon, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon, size: 14)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: - Menu bar

    private var menuBarSection: some View {
        section("Menu bar") {
            HStack(spacing: 14) {
                // A stand-in for the menu bar, dark and light.
                ForEach([true, false], id: \.self) { dark in
                    Image(nsImage: PillRenderer.image(for: sample, style: settings.pillStyle, darkMenuBar: dark))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(dark ? Color(white: 0.17) : Color(white: 0.88))
                        )
                }
                Spacer()
                Picker("Time", selection: $settings.displayStyle) {
                    Text("25m").tag(DisplayStyle.compact)
                    Text("24:59").tag(DisplayStyle.precise)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
            }

            HStack(spacing: 8) {
                Text("Bar colour")
                    .frame(width: 80, alignment: .leading)
                ForEach(AppSettings.palette, id: \.self) { hex in
                    swatch(hex)
                }
                Spacer()
                TextField("#A855F7", text: $hexDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 84)
                    .onSubmit(applyHex)
                    .onChange(of: hexDraft) { _, _ in applyHex() }
            }

            HStack(spacing: 8) {
                Text("Opacity")
                    .frame(width: 80, alignment: .leading)
                Slider(value: $settings.barOpacity, in: 0.1...1)
                Text("\(Int((settings.barOpacity * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text("Weight")
                    .frame(width: 80, alignment: .leading)
                Picker("Weight", selection: $settings.pillFontWeight) {
                    ForEach(PillFontWeight.allCases, id: \.self) { weight in
                        Text(weight.title).tag(weight)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Text("Width")
                    .frame(width: 80, alignment: .leading)
                Picker("Width", selection: $settings.pillWidthIsFixed) {
                    Text("Fixed").tag(true)
                    Text("Fits the time").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                if settings.pillWidthIsFixed {
                    // Whole pixels, without the tick marks a stepped slider draws.
                    Slider(value: Binding(
                        get: { settings.pillFixedWidth },
                        set: { settings.pillFixedWidth = $0.rounded() }
                    ), in: PillWidth.fixedRange)
                    Text("\(Int(settings.pillFixedWidth)) px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                    Stepper("Width", value: $settings.pillFixedWidth, in: PillWidth.fixedRange, step: 1)
                        .labelsHidden()
                } else {
                    Text("Grows and shrinks with the time shown.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .font(.system(size: 13))
    }

    private var sample: PillContent {
        PillContent(text: settings.displayStyle == .compact ? "25m" : "24:59", fraction: 0.62)
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = RGB(hex: hex) == RGB(hex: settings.barColorHex)
        return Circle()
            .fill(Color(nsColor: NSColor(hex: hex) ?? .clear))
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
            .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-4).opacity(isSelected ? 1 : 0))
            .contentShape(Circle())
            .onTapGesture {
                settings.barColorHex = hex
                hexDraft = hex
            }
    }

    private func applyHex() {
        guard let rgb = RGB(hex: hexDraft), rgb != RGB(hex: settings.barColorHex) else { return }
        settings.barColorHex = rgb.hex
    }

    // MARK: - Shortcut

    private var shortcutSection: some View {
        section("Shortcut") {
            HStack(spacing: 10) {
                Text("Open \(AppVariant.name)")
                Spacer()
                ShortcutRecorder(settings: settings)
            }
            if settings.hotKeyUnavailable {
                Text("macOS wouldn't register that shortcut. Pick another.")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 13))
    }

    // MARK: - General

    private var generalSection: some View {
        section("General") {
            Toggle("Play a sound when the timer ends", isOn: $settings.soundEnabled)
            Toggle("Glow around the screen when the timer ends", isOn: $settings.glowEnabled)
            Toggle("Open at login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    do {
                        try LoginItem.setEnabled(enabled)
                        loginItemError = nil
                    } catch {
                        loginItemError = error.localizedDescription
                    }
                    launchAtLogin = LoginItem.isEnabled
                }
            ))
            .disabled(!LoginItem.isAvailable)
            if let loginItemError {
                Text(loginItemError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 13))
        .toggleStyle(.checkbox)
    }

    // MARK: - Updates

    private var updatesSection: some View {
        section("Updates") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(updates.versionText)
                    Text(updates.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(updates.status.isFailure ? Color.red : Color.secondary)
                        .lineLimit(3)
                }
                Spacer()
                if case .available = updates.status {
                    Button("Update", action: updates.install)
                } else {
                    Button("Check for updates", action: updates.check)
                        .disabled(!updates.canCheck)
                }
            }
        }
        .font(.system(size: 13))
    }
}

/// Click, then press the new shortcut. Escape keeps the old one.
private struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(settings.isRecordingShortcut ? "Press a shortcut…" : settings.hotKey.display)
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 120)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(settings.isRecordingShortcut ? 0.18 : 0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: settings.isRecordingShortcut) { _, isRecording in
            if !isRecording { removeMonitor() }
        }
        .onDisappear(perform: removeMonitor)
    }

    private func toggle() {
        if settings.isRecordingShortcut {
            settings.isRecordingShortcut = false
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        settings.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                settings.isRecordingShortcut = false
            } else if let combo = KeyCombo(event: event) {
                settings.hotKey = combo
                settings.isRecordingShortcut = false
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
