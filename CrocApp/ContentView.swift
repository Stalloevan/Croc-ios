import SwiftUI
import UIKit

extension Color {
    /// The dark navy of the favicon outline; readable on the accent green.
    static let onAccent = Color(red: 1.0 / 255, green: 20.0 / 255, blue: 60.0 / 255)
    static let appBackground = Color("AppBackground")
    static let panel = Color("Panel")
}

/// One screen: pick Send or Receive at the top, settings live in a sheet.
struct ContentView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case send = "Send"
        case receive = "Receive"
        var id: String { rawValue }
        var symbol: String { self == .send ? "square.and.arrow.up" : "square.and.arrow.down" }
    }

    @EnvironmentObject private var model: TransferModel
    @State private var mode: Mode = .send
    @State private var showingSettings = false
    @State private var showingPicker = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ModeSwitch(mode: $mode)
                        .disabled(model.status.isWorking)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch mode {
                case .send: sendSections
                case .receive: receiveSections
                }

                StatusSection()
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Croc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("CrocMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .accessibilityHidden(true)
                        Text("croc").font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsSheet() }
            .sheet(isPresented: $showingPicker) {
                DocumentPicker(
                    onPick: { urls in
                        showingPicker = false
                        model.addFiles(urls)
                    },
                    onCancel: { showingPicker = false }
                )
                .ignoresSafeArea()
            }
        }
        .fontDesign(.monospaced)
    }

    private func copyCode() {
        guard !model.sendCode.isEmpty else { return }
        UIPasteboard.general.string = model.sendCode
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run { withAnimation { copied = false } }
        }
    }

    // MARK: Send

    @ViewBuilder private var sendSections: some View {
        Section {
            Text(model.sendCode.isEmpty ? "—" : model.sendCode)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)

            HStack {
                Button { copyCode() } label: {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copied ? Color.green : Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(copied ? "Code copied" : "Copy code")
                Spacer()
                ShareLink(item: model.sendCode) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button { model.regenerateCode() } label: {
                    Label("New", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .disabled(model.status.isWorking || model.sendCode.isEmpty)
        } header: {
            Text("Code").tracking(1.5)
        } footer: {
            Text("Give this code to the receiver and keep Croc open until the transfer finishes.")
        }
        .listRowBackground(Color.panel)

        Section {
            ForEach(model.selectedFiles, id: \.self) { url in
                Label(url.lastPathComponent, systemImage: "doc")
            }
            .onDelete { model.removeFiles(at: $0) }

            Button { showingPicker = true } label: {
                VStack(spacing: 6) {
                    Text(model.selectedFiles.isEmpty ? "Choose files" : "Add more files")
                        .font(.headline)
                    Text("Select from this device")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 92)
                .overlay(
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(.secondary)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.status.isWorking)
            .listRowSeparator(.hidden)
        } header: {
            Text("Files").tracking(1.5)
        }
        .listRowBackground(Color.panel)

        Section {
            Button { model.sendSelectedFiles() } label: {
                ActionLabel(title: "Send", busyTitle: "Sending…", systemImage: "square.and.arrow.up", busy: model.status.isWorking)
            }
            .buttonStyle(ActionButtonStyle())
            .disabled(model.status.isWorking || model.selectedFiles.isEmpty)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: Receive

    @ViewBuilder private var receiveSections: some View {
        Section {
            HStack {
                TextField("e.g. mouth-ripen-baker", text: $model.receiveCode)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { model.receiveFiles() }
                Button {
                    if let text = UIPasteboard.general.string { model.receiveCode = text }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Paste code")
            }
        } header: {
            Text("Code").tracking(1.5)
        } footer: {
            Text("Type or paste the code the sender sees. Files land in Files → Croc → Received.")
        }
        .listRowBackground(Color.panel)

        Section {
            Button { model.receiveFiles() } label: {
                ActionLabel(title: "Receive", busyTitle: "Receiving…", systemImage: "square.and.arrow.down", busy: model.status.isWorking)
            }
            .buttonStyle(ActionButtonStyle())
            .disabled(model.status.isWorking || model.receiveCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

// MARK: - Pieces

/// Send / Receive switch in the website's style: two flat halves, the selected one inverted.
struct ModeSwitch: View {
    @Binding var mode: ContentView.Mode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Mode.allCases) { item in
                let selected = item == mode
                Button { mode = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(selected ? Color.panel : Color.secondary)
                        .background(selected ? Color.primary : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .overlay(Rectangle().stroke(Color.primary, lineWidth: 1))
        .background(Color.panel)
    }
}

/// Primary action: accent green with the favicon's navy text.
struct ActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Button label. It never shows a spinner: the status row owns the only one.
struct ActionLabel: View {
    let title: String
    let busyTitle: String
    let systemImage: String
    let busy: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(busy ? busyTitle : title)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Progress and result of the current transfer.
struct StatusSection: View {
    @EnvironmentObject private var model: TransferModel

    var body: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .working(let message):
            // The one and only spinner on screen.
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(message)
                }
            }
            .listRowBackground(Color.panel)
        case .success(let message):
            Section {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if model.canShowReceived {
                    Button { model.showReceivedFolder() } label: {
                        Label("Show in Files", systemImage: "folder")
                    }
                }
                Button("Dismiss") { model.clearStatus() }
            }
            .listRowBackground(Color.panel)
        case .notice(let message):
            Section {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                }
                Button("Dismiss") { model.clearStatus() }
            }
            .listRowBackground(Color.panel)
        case .failure(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Dismiss") { model.clearStatus() }
            }
            .listRowBackground(Color.panel)
        }
    }
}

/// Relay settings, shown as a sheet from the gear button.
struct SettingsSheet: View {
    @EnvironmentObject private var model: TransferModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Automatic (public relays)", text: $model.relay)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Password (optional)", text: $model.relayPassword)
                } header: {
                    Text("Relay").tracking(1.5)
                } footer: {
                    Text("Leave the relay empty to use the public croc relays, chosen automatically from the code like other croc apps. Set host:port only to use your own relay on both sides.")
                }
                .listRowBackground(Color.panel)

                Section {
                    Toggle("Keep running in background", isOn: $model.keepRunning)
                } header: {
                    Text("Background").tracking(1.5)
                } footer: {
                    Text("Lets a transfer carry on while you switch to another app, such as a browser, by playing inaudible audio. Uses more battery while a transfer is running.")
                }
                .listRowBackground(Color.panel)

                Section {
                    Button("Back to automatic") { model.resetSettings() }
                }
                .listRowBackground(Color.panel)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fontDesign(.monospaced)
        .presentationDetents([.medium, .large])
    }
}
