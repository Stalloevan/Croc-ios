import SwiftUI
import UIKit

/// One screen, laid out like getcroc.com: Send / Receive / SSH tabs, square bordered panels.
struct ContentView: View {
    enum Mode: String, CaseIterable, Hashable {
        case send = "Send", receive = "Receive", ssh = "SSH"
        var symbol: String {
            switch self {
            case .send: return "square.and.arrow.up"
            case .receive: return "square.and.arrow.down"
            case .ssh: return "terminal"
            }
        }
    }
    enum Content: String, CaseIterable, Hashable { case files = "Files", text = "Text" }

    @EnvironmentObject private var model: TransferModel
    @EnvironmentObject private var ssh: SSHController
    @State private var mode: Mode = .send
    @State private var content: Content = .files
    @State private var showingSettings = false
    @State private var showingPicker = false
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    SiteTabs(items: Mode.allCases, selection: $mode, title: { $0.rawValue }, symbol: { $0.symbol })
                        .disabled(model.status.isWorking)
                    switch mode {
                    case .send: sendPanels
                    case .receive: receivePanels
                    case .ssh: SSHJoinPanel()
                    }
                    StatusPanel()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .fontDesign(.monospaced)
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
        .fullScreenCover(isPresented: $ssh.showTerminal) { SSHTerminalView() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("CrocMark")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            Text("croc").font(.title2.weight(.bold))
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").frame(width: 24, height: 24)
            }
            .buttonStyle(OutlineButtonStyle())
            .accessibilityLabel("Settings")
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

    @ViewBuilder private var sendPanels: some View {
        Panel(title: "Code") {
            Text(model.sendCode.isEmpty ? "—" : model.sendCode)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            HStack(spacing: 8) {
                Button { copyCode() } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(OutlineButtonStyle(tint: copied ? .accentColor : .ink))
                .accessibilityLabel(copied ? "Code copied" : "Copy code")
                ShareLink(item: model.sendCode) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle())
                Button { model.regenerateCode() } label: {
                    Label("New", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle())
            }
            .disabled(model.status.isWorking || model.sendCode.isEmpty)
            Text("Give this code to the receiver and keep Croc open until the transfer finishes.")
                .font(.footnote).foregroundStyle(Color.muted)
        }

        SiteTabs(items: Content.allCases, selection: $content, title: { $0.rawValue })
            .disabled(model.status.isWorking)

        if content == .files {
            Panel(title: "Files") {
                ForEach(model.selectedFiles, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(systemName: "doc").foregroundStyle(Color.muted)
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { remove(url) } label: {
                            Image(systemName: "xmark").frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.muted)
                        .disabled(model.status.isWorking)
                        .accessibilityLabel("Remove \(url.lastPathComponent)")
                    }
                }
                Button { showingPicker = true } label: {
                    VStack(spacing: 6) {
                        Text(model.selectedFiles.isEmpty ? "Choose files" : "Add more files").font(.headline)
                        Text("Select from this device").font(.footnote).foregroundStyle(Color.muted)
                    }
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .overlay(
                        Rectangle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(Color.muted)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.status.isWorking)
            }
            Button { model.sendSelectedFiles() } label: {
                ActionLabel(title: "Send", busyTitle: "Sending…", systemImage: "square.and.arrow.up", busy: model.status.isWorking)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.status.isWorking || model.selectedFiles.isEmpty)
        } else {
            Panel(title: "Message") {
                TextEditor(text: $model.textToSend)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(Color.canvas)
                    .overlay(Rectangle().stroke(Color.softBorder, lineWidth: 1))
                    .textInputAutocapitalization(.never)
                    .disabled(model.status.isWorking)
                Text("Up to 1 MiB. The receiver sees it on screen; nothing is saved to a file.")
                    .font(.footnote).foregroundStyle(Color.muted)
            }
            Button { model.sendTypedText() } label: {
                ActionLabel(title: "Send text", busyTitle: "Sending…", systemImage: "text.bubble", busy: model.status.isWorking)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.status.isWorking || model.textToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func remove(_ url: URL) {
        if let index = model.selectedFiles.firstIndex(of: url) {
            model.removeFiles(at: IndexSet(integer: index))
        }
    }

    // MARK: Receive

    @ViewBuilder private var receivePanels: some View {
        Panel(title: "Code") {
            HStack(spacing: 8) {
                TextField("e.g. mouth-ripen-baker", text: $model.receiveCode)
                    .font(.system(.body, design: .monospaced))
                    .submitLabel(.go)
                    .onSubmit { model.receiveFiles() }
                    .siteField()
                Button {
                    if let text = UIPasteboard.general.string { model.receiveCode = text }
                } label: {
                    Image(systemName: "doc.on.clipboard").frame(width: 24, height: 24)
                }
                .buttonStyle(OutlineButtonStyle())
                .frame(minHeight: 46)
                .accessibilityLabel("Paste code")
            }
            Text("Type or paste the code the sender sees. Files land in Files → Croc → Received; text appears below.")
                .font(.footnote).foregroundStyle(Color.muted)
        }
        Button { model.receiveFiles() } label: {
            ActionLabel(title: "Receive", busyTitle: "Receiving…", systemImage: "square.and.arrow.down", busy: model.status.isWorking)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(model.status.isWorking || model.receiveCode.trimmingCharacters(in: .whitespaces).isEmpty)

        if let text = model.receivedText {
            Panel(title: "Message received") {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = text
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                    ShareLink(item: text) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                    Button { model.clearStatus() } label: {
                        Label("Dismiss", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
            }
        }
    }
}

// MARK: - Pieces

/// Button label. It never shows a spinner: the status panel owns the only one.
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
struct StatusPanel: View {
    @EnvironmentObject private var model: TransferModel

    var body: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .working(let message):
            // The one and only spinner on screen.
            Panel {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(message)
                }
            }
        case .success(let message):
            Panel {
                Label(message, systemImage: "checkmark.square.fill").foregroundStyle(Color.accentColor)
                HStack(spacing: 8) {
                    if model.canShowReceived {
                        Button { model.showReceivedFolder() } label: {
                            Label("Show in Files", systemImage: "folder").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }
                    Button { model.clearStatus() } label: { Text("Dismiss").frame(maxWidth: .infinity) }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
        case .notice(let message):
            Panel {
                Label(message, systemImage: "hand.raised.fill")
                Button { model.clearStatus() } label: { Text("Dismiss").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle())
            }
        case .failure(let message):
            Panel {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                Button { model.clearStatus() } label: { Text("Dismiss").frame(maxWidth: .infinity) }
                    .buttonStyle(OutlineButtonStyle())
            }
        }
    }
}

/// Relay settings, shown as a sheet from the gear button.
struct SettingsSheet: View {
    @EnvironmentObject private var model: TransferModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Settings").font(.title2.weight(.bold))
                        Spacer()
                        Button("Done") { dismiss() }.buttonStyle(OutlineButtonStyle())
                    }
                    Panel(title: "Relay") {
                        TextField("Automatic (public relays)", text: $model.relay)
                            .keyboardType(.URL)
                            .siteField()
                        SecureField("Password (optional)", text: $model.relayPassword)
                            .siteField()
                        Text("Leave the relay empty to use the public croc relays, chosen automatically from the code like other croc apps. Set host:port only to use your own relay on both sides.")
                            .font(.footnote).foregroundStyle(Color.muted)
                    }
                    Panel(title: "Background") {
                        SiteCheckbox(title: "Keep running in background", isOn: $model.keepRunning)
                        Text("Lets a transfer carry on while you switch to another app, such as a browser, by playing inaudible audio. Uses more battery while a transfer is running.")
                            .font(.footnote).foregroundStyle(Color.muted)
                    }
                    Button { model.resetSettings() } label: {
                        Text("Back to automatic").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
                .padding(16)
            }
        }
        .fontDesign(.monospaced)
        .presentationBackground(Color.canvas)
        .presentationDetents([.medium, .large])
    }
}
