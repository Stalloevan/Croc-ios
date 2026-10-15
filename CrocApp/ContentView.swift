import SwiftUI
import UIKit

/// One screen: pick Send or Receive at the top, settings live in a sheet.
struct ContentView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case send = "Send"
        case receive = "Receive"
        var id: String { rawValue }
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
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.status.isWorking)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                switch mode {
                case .send: sendSections
                case .receive: receiveSections
                }

                StatusSection()
            }
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
                        Text("Croc").font(.headline)
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
            Text("Code")
        } footer: {
            Text("Give this code to the receiver and keep Croc open until the transfer finishes.")
        }

        Section("Files") {
            if model.selectedFiles.isEmpty {
                Text("No files yet. Add the files you want to send.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.selectedFiles, id: \.self) { url in
                Label(url.lastPathComponent, systemImage: "doc")
            }
            .onDelete { model.removeFiles(at: $0) }

            Button { showingPicker = true } label: {
                Label("Add files", systemImage: "plus.circle.fill")
            }
            .disabled(model.status.isWorking)
        }

        Section {
            Button { model.sendSelectedFiles() } label: {
                ActionLabel(title: "Send", systemImage: "paperplane.fill", busy: model.status.isWorking)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
            Text("Code")
        } footer: {
            Text("Type or paste the code the sender sees. Files land in Files → Croc → Received.")
        }

        Section {
            Button { model.receiveFiles() } label: {
                ActionLabel(title: "Receive", systemImage: "arrow.down.circle.fill", busy: model.status.isWorking)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.status.isWorking || model.receiveCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

// MARK: - Pieces

/// Button label that swaps to a spinner while a transfer runs.
struct ActionLabel: View {
    let title: String
    let systemImage: String
    let busy: Bool

    var body: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().tint(.white)
                Text("Working…")
            } else {
                Image(systemName: systemImage)
                Text(title)
            }
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
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(message)
                }
            }
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
        case .notice(let message):
            Section {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                }
                Button("Dismiss") { model.clearStatus() }
            }
        case .failure(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Dismiss") { model.clearStatus() }
            }
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
                    Text("Relay")
                } footer: {
                    Text("Leave the relay empty to use the public croc relays, chosen automatically from the code like other croc apps. Set host:port only to use your own relay on both sides.")
                }

                Section {
                    Toggle("Keep running in background", isOn: $model.keepRunning)
                } header: {
                    Text("Background")
                } footer: {
                    Text("Lets a transfer carry on while you switch to another app, such as a browser, by playing inaudible audio. Uses more battery while a transfer is running.")
                }

                Section {
                    Button("Back to automatic") { model.resetSettings() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
