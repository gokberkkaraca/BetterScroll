import SwiftUI
import IOKit.hid
import ServiceManagement

struct SettingsPanel: View {
    private enum Tab: String, CaseIterable {
        case scrolling = "Scrolling", buttons = "Buttons", gestures = "Gestures"
    }

    @ObservedObject var app: App
    @State private var tab = Tab.scrolling

    private var ready: Bool { !app.busy && app.originalWheel != nil }

    var body: some View {
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        VStack(alignment: .leading, spacing: 14) {
            header
            if !accessibility || !inputMonitoring {
                VStack(alignment: .leading, spacing: 8) {
                    if !accessibility {
                        Button("Allow Accessibility…") { app.select(.accessibility) }
                    }
                    if !inputMonitoring {
                        Button("Allow Input Monitoring…") { app.select(.inputMonitoring) }
                    }
                }
            }

            Picker("Settings", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            Group {
                switch tab {
                case .scrolling: scrolling(accessibility: accessibility)
                case .buttons: buttonMappings(accessibility: accessibility)
                case .gestures: gestures
                }
            }
            .frame(minHeight: 172, alignment: .topLeading)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

            Divider()
            if #available(macOS 13, *) {
                LoginItemSetting()
            }
            footer
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.discovery.mouse?.model.name ?? "BetterScroll")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)
                    Text(app.status.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusSymbol: String {
        switch app.status {
        case .connected: return "circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .waiting, .contacting: return "circle"
        }
    }

    private var statusColor: Color {
        switch app.status {
        case .connected: return .green
        case .error: return .orange
        case .waiting, .contacting: return .secondary
        }
    }

    private func scrolling(accessibility: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { app.smooth && accessibility }, set: { _ in app.select(.smooth) }
            )) {
                Text("Smooth vertical scrolling").frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!ready || !accessibility)
            Toggle(isOn: Binding(
                get: { app.reverse }, set: { _ in app.select(.reverse) }
            )) {
                Text("Reverse vertical direction").frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!ready)

            Divider().padding(.vertical, 4)

            Text("Wheel mode").fontWeight(.semibold)
            Picker("Wheel mode", selection: Binding(
                get: { app.currentMode }, set: { app.select(.mode($0)) }
            )) {
                ForEach(modes.indices, id: \.self) { Text(modes[$0]).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!ready)
            Text("The wheel mode button cycles through all three modes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
    }

    private func buttonMappings(accessibility: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(buttons.filter { $0.0 != modeButton }, id: \.0) { cid, title in
                let choices = cid == thumb ? actions + ["Hold for gestures"] : actions
                mapping(title, choices: choices, selection: Binding(
                    get: { app.action(for: cid) }, set: { app.select(.button(cid, $0)) }
                ))
                .disabled(!ready || !accessibility || app.originals[cid] == nil)
            }
        }
    }

    private var gestures: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ThumbInput.allCases, id: \.self) { input in
                let title = input == .tap ? "Tap" : "Hold + \(input.rawValue)"
                mapping(title, choices: gestureChoices, selection: Binding(
                    get: { gestureChoices.firstIndex(of: input.mapping(in: defaults)) ?? 0 },
                    set: { app.select(.gesture(input, gestureChoices[$0])) }
                ))
            }

            Text(app.action(for: thumb) == gesturesAction
                 ? "Hold the thumb button while moving the mouse."
                 : "To use gestures, choose “Hold for gestures” in Buttons.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
    }

    private func mapping(_ title: String, choices: [String], selection: Binding<Int>) -> some View {
        HStack {
            Text(title).accessibilityHidden(true)
            Spacer(minLength: 8)
            MappingPicker(title: title, choices: choices, selection: selection)
                .frame(width: 172, height: 24)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                app.select(.updates)
            } label: {
                Label(app.checkingUpdates ? "Checking for Updates…" : "Check for Updates…",
                      systemImage: "arrow.down.circle")
            }
            .disabled(app.checkingUpdates)

            Spacer(minLength: 0)

            Button("Hide Menu Bar Icon") { app.select(.hideMenuBarIcon) }
                .help("Open BetterScroll from Applications to show the icon again.")

            Button("Quit") { app.select(.quit) }
                .accessibilityLabel("Quit BetterScroll")
        }
        .buttonStyle(FooterButtonStyle())
        .font(.callout)
    }
}

private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Highlight(configuration: configuration)
    }

    private struct Highlight: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        private var highlightOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.22 }
            return hovered ? 0.14 : 0
        }

        var body: some View {
            configuration.label
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .background(Color.primary.opacity(highlightOpacity), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}

@available(macOS 13, *)
private struct LoginItemSetting: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: Binding(
                get: { status == .enabled || status == .requiresApproval }, set: setEnabled
            )) {
                Text("Open at Login").frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)

            if status == .requiresApproval {
                Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if let failure {
                Text(failure)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        failure = nil
        defer { status = service.status }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            if !enabled || service.status != .requiresApproval {
                failure = "Couldn’t change Open at Login. \(error.localizedDescription)"
            }
        }
    }
}

private struct MappingPicker: NSViewRepresentable {
    let title: String
    let choices: [String]
    @Binding var selection: Int
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if button.itemTitles != choices {
            button.removeAllItems()
            button.addItems(withTitles: choices)
        }
        button.selectItem(at: choices.indices.contains(selection) ? selection : 0)
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Int>?

        @objc func choose(_ sender: NSPopUpButton) {
            if sender.indexOfSelectedItem >= 0 {
                selection?.wrappedValue = sender.indexOfSelectedItem
            }
        }
    }
}
