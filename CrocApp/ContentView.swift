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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CrocHeader(mode: mode)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Swamp settings")
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

    // MARK: Send

    @ViewBuilder private var sendSections: some View {
        Section {
            Text(model.sendCode.isEmpty ? "—" : model.sendCode)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)

            HStack {
                Button {
                    UIPasteboard.general.string = model.sendCode
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
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
            Text("Swamp code")
        } footer: {
            Text("Give this code to the receiver and keep Croc open until the transfer finishes.")
        }

        Section("The catch") {
            if model.selectedFiles.isEmpty {
                Text("Nothing here yet. Add the files you want to send.")
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
                ActionLabel(title: "Snap it over", systemImage: "paperplane.fill", busy: model.status.isWorking)
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
            Text("Swamp code")
        } footer: {
            Text("Type or paste the code the sender sees. Files land in Files → Croc → Received.")
        }

        Section {
            Button { model.receiveFiles() } label: {
                ActionLabel(title: "Chomp it down", systemImage: "arrow.down.circle.fill", busy: model.status.isWorking)
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

/// Mascot and one-line description for the current mode.
struct CrocHeader: View {
    let mode: ContentView.Mode

    var body: some View {
        VStack(spacing: 4) {
            CrocGlyphView(size: 56)
            Text(mode == .send ? "Snap files across" : "Chomp files down")
                .font(.title3.weight(.semibold))
            Text(mode == .send
                 ? "Pick files, share the swamp code, done."
                 : "Enter the swamp code to grab files.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

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
    @State private var wobble = false

    var body: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .working(let message):
            Section {
                HStack(spacing: 12) {
                    CrocGlyphView(size: 30)
                        .rotationEffect(.degrees(wobble ? 8 : -8))
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: wobble)
                        .onAppear { wobble = true }
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
                    TextField("host:port", text: $model.relay)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Password (optional)", text: $model.relayPassword)
                } header: {
                    Text("Swamp relay")
                } footer: {
                    Text("Both sides must use the same relay. Leave these alone to use the public croc relay.")
                }

                Section {
                    Toggle("Keep running in background", isOn: $model.keepRunning)
                } header: {
                    Text("Background")
                } footer: {
                    Text("Lets a transfer carry on while you switch to another app, such as a browser, by playing inaudible audio. Uses more battery while a transfer is running.")
                }

                Section {
                    Button("Back to the public relay") { model.resetSettings() }
                }
            }
            .navigationTitle("Swamp settings")
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
