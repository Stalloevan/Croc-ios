import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        TabView {
            SendView()
                .tabItem { Label("Send", systemImage: "arrow.up.circle") }
            ReceiveView()
                .tabItem { Label("Receive", systemImage: "arrow.down.circle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct SendView: View {
    @EnvironmentObject private var model: TransferModel
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Code") {
                    Text(model.sendCode.isEmpty ? "—" : model.sendCode)
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                    Button("New code") { model.regenerateCode() }
                    Text("Give this code to the receiver. Keep this screen open until the transfer finishes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Files") {
                    ForEach(model.selectedFiles, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "doc")
                    }
                    .onDelete { model.removeFiles(at: $0) }

                    Button("Add files…") { showingImporter = true }
                }

                Section {
                    Button {
                        model.sendSelectedFiles()
                    } label: {
                        if model.status.isWorking {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(model.status.isWorking || model.selectedFiles.isEmpty)
                }

                StatusSection()
            }
            .navigationTitle("Send")
            .sheet(isPresented: $showingImporter) {
                DocumentPicker(
                    onPick: { urls in
                        showingImporter = false
                        model.addFiles(urls)
                    },
                    onCancel: { showingImporter = false }
                )
                .ignoresSafeArea()
            }
        }
    }
}

struct ReceiveView: View {
    @EnvironmentObject private var model: TransferModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Code") {
                    TextField("Code from the sender", text: $model.receiveCode)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        model.receiveFiles()
                    } label: {
                        if model.status.isWorking {
                            ProgressView()
                        } else {
                            Text("Receive")
                        }
                    }
                    .disabled(model.status.isWorking || model.receiveCode.isEmpty)
                }

                StatusSection()
            }
            .navigationTitle("Receive")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: TransferModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Relay host:port", text: $model.relay)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Relay password (optional)", text: $model.relayPassword)
                } header: {
                    Text("Relay")
                } footer: {
                    Text("Both sides must use the same relay. Leave the default to use the public croc relay.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

/// Shows progress and the final result for the current transfer.
struct StatusSection: View {
    @EnvironmentObject private var model: TransferModel

    var body: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .working(let message):
            Section("Status") {
                Label(message, systemImage: "hourglass")
            }
        case .success(let message):
            Section("Status") {
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Button("Dismiss") { model.clearStatus() }
            }
        case .failure(let message):
            Section("Status") {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Dismiss") { model.clearStatus() }
            }
        }
    }
}
