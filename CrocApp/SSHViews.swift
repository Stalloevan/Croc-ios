import SwiftUI

/// SSH tab: paste the six-word invitation from `croc ssh` and join the shared terminal.
struct SSHJoinPanel: View {
    @EnvironmentObject private var model: TransferModel
    @EnvironmentObject private var ssh: SSHController
    @State private var showCode = false

    var body: some View {
        Panel(title: "Join a shared terminal") {
            HStack(spacing: 8) {
                Group {
                    if showCode {
                        TextField("six-word SSH code", text: $ssh.code)
                    } else {
                        SecureField("six-word SSH code", text: $ssh.code)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .submitLabel(.go)
                .onSubmit { join() }
                .siteField()
                Button { showCode.toggle() } label: {
                    Image(systemName: showCode ? "eye.slash" : "eye").frame(width: 24, height: 24)
                }
                .buttonStyle(OutlineButtonStyle())
                .frame(minHeight: 46)
                .accessibilityLabel(showCode ? "Hide code" : "Show code")
                Button {
                    if let text = UIPasteboard.general.string { ssh.code = text }
                } label: {
                    Image(systemName: "doc.on.clipboard").frame(width: 24, height: 24)
                }
                .buttonStyle(OutlineButtonStyle())
                .frame(minHeight: 46)
                .accessibilityLabel("Paste code")
            }
            Text("Run `croc ssh` on the host computer and paste the read/write or read-only code it prints. The terminal runs through the croc relay, end to end encrypted.")
                .font(.footnote).foregroundStyle(Color.muted)
            if let error = ssh.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote)
            }
            if case .ended(let message) = ssh.state, !message.isEmpty {
                Label(message, systemImage: "info.square").font(.footnote)
            }
            if case .failed(let message) = ssh.state {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote)
            }
        }
        Button { join() } label: {
            ActionLabel(title: "Join", busyTitle: "Joining…", systemImage: "terminal", busy: ssh.isActive)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(ssh.isActive || ssh.code.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func join() {
        ssh.relay = model.relay
        ssh.relayPassword = model.relayPassword
        ssh.keepRunning = model.keepRunning
        ssh.join()
    }
}

/// Full-screen terminal with a slim square header.
struct SSHTerminalView: View {
    @EnvironmentObject private var ssh: SSHController

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { ssh.leave() } label: {
                        Label("Leave", systemImage: "xmark").frame(minHeight: 24)
                    }
                    .buttonStyle(OutlineButtonStyle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusText).font(.subheadline.weight(.semibold))
                        if !ssh.role.isEmpty {
                            Text(ssh.role == "read-write" ? "Read/write" : "Read-only")
                                .font(.caption).foregroundStyle(Color.muted)
                        }
                    }
                    Spacer()
                    if ssh.state == .connecting || ssh.state == .reconnecting {
                        ProgressView()
                    }
                }
                .padding(12)
                .background(Color.canvas)
                Rectangle().fill(Color.ink).frame(height: 1)
                TerminalScreen(controller: ssh)
                    .background(Color.panel)
                    .padding(.horizontal, 1)
            }
        }
        .fontDesign(.monospaced)
        .onChange(of: ssh.state) { _, state in
            switch state {
            case .ended, .failed: ssh.showTerminal = false
            default: break
            }
        }
    }

    private var statusText: String {
        switch ssh.state {
        case .idle, .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .ended: return "Disconnected"
        case .failed: return "Failed"
        }
    }
}
