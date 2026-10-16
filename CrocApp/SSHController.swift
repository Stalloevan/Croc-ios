import Foundation
import SwiftTerm
import SwiftUI
import UIKit

/// Owns one joined SSH terminal: the Go session, and the SwiftTerm view that draws it.
@MainActor
final class SSHController: ObservableObject {
    enum State: Equatable {
        case idle, connecting, connected, reconnecting
        case ended(String)
        case failed(String)
    }

    @Published var code = ""
    @Published var state: State = .idle
    @Published var role = ""
    /// "tailcat" (direct) or "relay" once connected.
    @Published var path = ""
    @Published var showTerminal = false
    @Published var error: String?

    private var session: CrocBridge.SSHHandle?
    private let keepAlive = BackgroundKeepAlive()
    weak var terminalView: TerminalView?
    private var pending: [[UInt8]] = []
    var relay = ""
    var relayPassword = ""
    var keepRunning = true

    var isActive: Bool {
        switch state {
        case .connecting, .connected, .reconnecting: return true
        default: return false
        }
    }

    var canJoin: Bool { CrocBridge.isValidSSHCode(code) }

    func join() {
        error = nil
        guard CrocBridge.isValidSSHCode(code) else {
            error = "Paste the six-word SSH code from the host."
            return
        }
        state = .connecting
        showTerminal = true
    }

    /// Called by the terminal view once it knows its size.
    func start(cols: Int, rows: Int) {
        guard session == nil, state == .connecting else { return }
        keepAlive.start(useAudio: keepRunning)
        let code = self.code, relay = self.relay, password = self.relayPassword
        Task.detached {
            do {
                let session = try CrocBridge.joinSSH(code: code, relay: relay, relayPassword: password,
                                                     cols: cols, rows: rows)
                await MainActor.run { self.session = session }
                Task.detached {
                    while let data = session.readOutput() {
                        let bytes = [UInt8](data)
                        await MainActor.run { self.receive(bytes) }
                    }
                }
                Task.detached {
                    while true {
                        let line = session.nextStatus()
                        if line.isEmpty { break }
                        let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                        guard parts.count == 3 else { continue }
                        await MainActor.run { self.status(parts[0], role: parts[1], message: parts[2]) }
                    }
                }
            } catch {
                await MainActor.run { self.finish(.failed(error.localizedDescription)) }
            }
        }
    }

    /// Keystrokes go through one serial queue so they can never be reordered.
    private let inputQueue = DispatchQueue(label: "croc.ssh.input", qos: .userInteractive)

    func send(_ data: ArraySlice<UInt8>) {
        guard role != "read-only", let session else { return }
        let bytes = Data(data)
        predict(bytes)
        inputQueue.async { session.sendInput(bytes) }
    }

    // MARK: Predictive local echo
    //
    // Typed characters are drawn at once instead of waiting for the network round trip. The
    // host's echo is then swallowed when it matches. Prediction only switches on after the host
    // has echoed a typed character back, so passwords (which are not echoed) are never drawn.

    private var predicted: [UInt8] = []
    private var echoTrusted = false
    /// Set after Enter or a control key; the next typed character must be echoed before prediction resumes.
    private var lineBreak = false

    private func predict(_ bytes: Data) {
        guard let view = terminalView else { return }
        guard bytes.count == 1, let byte = bytes.first, (0x20...0x7e).contains(byte) else {
            // Enter, control keys, escape sequences: the line state is the host's to decide.
            echoTrusted = false
            lineBreak = true
            return
        }
        guard echoTrusted, !view.getTerminal().isCurrentBufferAlternate else {
            lastTypedUntrusted = byte
            return
        }
        predicted.append(byte)
        view.feed(byteArray: [byte][...])
    }

    private var lastTypedUntrusted: UInt8?

    /// Output from the host, with already-drawn predictions removed.
    private func reconcile(_ incoming: [UInt8]) -> [UInt8] {
        var data = incoming
        if !predicted.isEmpty {
            var matched = 0
            while matched < predicted.count, matched < data.count, data[matched] == predicted[matched] {
                matched += 1
            }
            if matched == predicted.count || matched == data.count {
                // Echo confirmed (fully or so far): drop the part already on screen.
                data.removeFirst(matched)
                predicted.removeFirst(matched)
                echoTrusted = !lineBreak
            } else {
                // The host did something else: erase the guesses and show the real output.
                let erase: [UInt8] = predicted.flatMap { _ in [UInt8(8), 32, 8] }
                terminalView?.feed(byteArray: erase[...])
                predicted.removeAll()
                echoTrusted = false
            }
        } else if let typed = lastTypedUntrusted {
            // A single typed character that the host echoes straight back earns trust.
            lastTypedUntrusted = nil
            if data.first == typed { echoTrusted = true; lineBreak = false }
        }
        return data
    }

    func leave() {
        let session = self.session
        Task.detached { session?.close() }
        finish(.idle)
        showTerminal = false
    }

    func attach(_ view: TerminalView) {
        terminalView = view
        for chunk in pending { view.feed(byteArray: chunk[...]) }
        pending.removeAll()
    }

    fileprivate func receive(_ incoming: [UInt8]) {
        let bytes = reconcile(incoming)
        if bytes.isEmpty { return }
        if let view = terminalView {
            view.feed(byteArray: bytes[...])
        } else {
            pending.append(bytes)
        }
    }

    fileprivate func status(_ newState: String, role: String, message: String) {
        if self.state == .idle { return }  // a session we already left
        if !role.isEmpty { self.role = role }
        if newState == "connected" { path = message }
        switch newState {
        case "connecting": self.state = .connecting
        case "connected": self.state = .connected
        case "reconnecting": self.state = .reconnecting
        case "ended": finish(.ended(message))
        case "failed": finish(.failed(message))
        default: break
        }
    }

    private func finish(_ final: State) {
        keepAlive.stop()
        session = nil
        state = final
    }
}

/// SwiftTerm's UIKit terminal, wired to an SSHController.
struct TerminalScreen: UIViewRepresentable {
    let controller: SSHController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = UIColor(red: 5 / 255, green: 6 / 255, blue: 5 / 255, alpha: 1)
        view.nativeForegroundColor = UIColor(white: 0.91, alpha: 1)
        view.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        controller.attach(view)
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    final class Coordinator: NSObject, TerminalViewDelegate {
        let controller: SSHController
        init(controller: SSHController) { self.controller = controller }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            Task { @MainActor in self.controller.start(cols: newCols, rows: newRows) }
        }
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            Task { @MainActor in self.controller.send(data) }
        }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link), url.scheme == "https" || url.scheme == "http" {
                UIApplication.shared.open(url)
            }
        }
        func clipboardCopy(source: TerminalView, content: Data) {
            UIPasteboard.general.string = String(data: content, encoding: .utf8)
        }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
