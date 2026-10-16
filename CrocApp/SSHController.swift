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
    @Published var showTerminal = false
    @Published var error: String?

    private var session: CrocmobileSSHSession?
    private var sink: Sink?
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
        let sink = Sink(owner: self)
        self.sink = sink
        keepAlive.start(useAudio: keepRunning)
        let code = self.code, relay = self.relay, password = self.relayPassword
        Task.detached {
            do {
                let session = try CrocBridge.joinSSH(code: code, relay: relay, relayPassword: password,
                                                     cols: cols, rows: rows, sink: sink)
                await MainActor.run { self.session = session }
            } catch {
                await MainActor.run { self.finish(.failed(error.localizedDescription)) }
            }
        }
    }

    func send(_ data: ArraySlice<UInt8>) {
        guard role != "read-only", let session else { return }
        let bytes = Data(data)
        Task.detached { session.sendInput(bytes) }
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

    fileprivate func receive(_ bytes: [UInt8]) {
        if let view = terminalView {
            view.feed(byteArray: bytes[...])
        } else {
            pending.append(bytes)
        }
    }

    fileprivate func status(_ state: String, role: String, message: String) {
        if !role.isEmpty { self.role = role }
        switch state {
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
        sink = nil
        state = final
    }

    /// Receives callbacks from Go on arbitrary threads.
    final class Sink: NSObject, CrocmobileTerminalSinkProtocol {
        weak var owner: SSHController?
        init(owner: SSHController) { self.owner = owner }

        func write(_ data: Data?) {
            guard let data else { return }
            let bytes = [UInt8](data)
            Task { @MainActor in self.owner?.receive(bytes) }
        }

        func status(_ state: String?, role: String?, message: String?) {
            let s = state ?? "", r = role ?? "", m = message ?? ""
            Task { @MainActor in self.owner?.status(s, role: r, message: m) }
        }
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
