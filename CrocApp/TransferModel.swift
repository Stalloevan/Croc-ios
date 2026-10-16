import Foundation
import UIKit

/// Holds app state and runs transfers. Heavy work runs on a background task;
/// UI-facing state is only touched on the main actor.
@MainActor
final class TransferModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case working(String)
        case success(String)
        /// Not an error: something the user should know about, such as a declined transfer.
        case notice(String)
        case failure(String)

        var isWorking: Bool {
            if case .working = self { return true }
            return false
        }
    }

    @Published var status: Status = .idle
    @Published var selectedFiles: [URL] = []
    @Published var sendCode: String = ""
    @Published var receiveCode: String = ""
    @Published var canShowReceived = false
    @Published var textToSend: String = ""
    /// A message received from the sender instead of files.
    @Published var receivedText: String?
    /// Remembered between launches. The password is kept for the session only.
    @Published var relay: String {
        didSet { UserDefaults.standard.set(relay, forKey: "relay") }
    }
    @Published var relayPassword: String = ""
    /// Keep transfers alive when the app is in the background (see BackgroundKeepAlive).
    @Published var keepRunning: Bool {
        didSet { UserDefaults.standard.set(keepRunning, forKey: "keepRunning") }
    }

    private let keepAlive = BackgroundKeepAlive()

    /// Received files are saved here and appear under "On My iPhone > Croc" in the Files app.
    var receiveFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Received", isDirectory: true)
    }

    init() {
        let savedRelay = UserDefaults.standard.string(forKey: "relay") ?? CrocBridge.defaultRelay
        // Earlier versions saved the old built-in default; that now means "automatic".
        relay = savedRelay == "croc.schollz.com:9009" ? CrocBridge.defaultRelay : savedRelay
        keepRunning = UserDefaults.standard.object(forKey: "keepRunning") as? Bool ?? true
        regenerateCode()
    }

    func resetSettings() {
        relay = CrocBridge.defaultRelay
        relayPassword = ""
    }

    /// Opens the received-files folder in the Files app.
    func showReceivedFolder() {
        let path = receiveFolder.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? receiveFolder.path
        if let url = URL(string: "shareddocuments://" + path) {
            UIApplication.shared.open(url)
        }
    }

    func regenerateCode() {
        do {
            sendCode = try CrocBridge.generateCode()
        } catch {
            status = .failure("Could not create a code: \(error.localizedDescription)")
        }
    }

    /// Copies picked files into a private staging folder. Security-scoped URLs from the
    /// document picker are only readable while access is open, and croc reads them later,
    /// so each file is copied before the send starts.
    func addFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let staging = FileManager.default.temporaryDirectory
                    .appendingPathComponent("outgoing", isDirectory: true)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let target = staging.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: url, to: target)
                selectedFiles.append(target)
            } catch {
                status = .failure("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func removeFiles(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where selectedFiles.indices.contains(index) {
            try? FileManager.default.removeItem(at: selectedFiles[index])
            selectedFiles.remove(at: index)
        }
    }

    func sendSelectedFiles() {
        guard !status.isWorking else { return }
        guard !selectedFiles.isEmpty else {
            status = .failure("Choose at least one file to send.")
            return
        }
        guard !sendCode.isEmpty else {
            status = .failure("Create a code first.")
            return
        }

        let files = selectedFiles
        let code = sendCode
        let relayAddress = self.relay
        let password = relayPassword
        status = .working("Waiting for the receiver…")
        keepAlive.start(useAudio: keepRunning)

        Task.detached(priority: .userInitiated) {
            do {
                try CrocBridge.send(files: files, code: code, relay: relayAddress, relayPassword: password)
                await self.finish(.success("Sent \(files.count) item(s)."), received: false)
            } catch {
                if CrocBridge.isDeclined(error) {
                    await self.finish(.notice("The receiver declined the transfer."), received: false)
                } else {
                    await self.finish(.failure(error.localizedDescription), received: false)
                }
            }
        }
    }

    func sendTypedText() {
        guard !status.isWorking else { return }
        let text = textToSend
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = .failure("Type a message to send.")
            return
        }
        guard !sendCode.isEmpty else {
            status = .failure("Create a code first.")
            return
        }
        let code = sendCode
        let relayAddress = self.relay
        let password = relayPassword
        status = .working("Waiting for the receiver…")
        keepAlive.start(useAudio: keepRunning)

        Task.detached(priority: .userInitiated) {
            do {
                try CrocBridge.sendText(text, code: code, relay: relayAddress, relayPassword: password)
                await self.finish(.success("Message sent."), received: false, clearText: true)
            } catch {
                if CrocBridge.isDeclined(error) {
                    await self.finish(.notice("The receiver declined the transfer."), received: false)
                } else {
                    await self.finish(.failure(error.localizedDescription), received: false)
                }
            }
        }
    }

    func receiveFiles() {
        guard !status.isWorking else { return }
        let code = receiveCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            status = .failure("Enter the code the sender shows.")
            return
        }

        let relayAddress = self.relay
        let password = relayPassword
        let destination = receiveFolder
        status = .working("Connecting to the sender…")
        receivedText = nil
        keepAlive.start(useAudio: keepRunning)

        Task.detached(priority: .userInitiated) {
            do {
                let text = try CrocBridge.receive(code: code, relay: relayAddress, relayPassword: password, destination: destination)
                if let text {
                    await self.finishText(text)
                } else {
                    await self.finish(.success("Files saved to Files → Croc → Received."), received: true)
                }
            } catch {
                await self.finish(.failure(error.localizedDescription), received: false)
            }
        }
    }

    func clearStatus() {
        if !status.isWorking {
            status = .idle
            receivedText = nil
            canShowReceived = false
        }
    }

    private func finishText(_ text: String) {
        keepAlive.stop()
        receivedText = text
        status = .idle
        canShowReceived = false
    }

    private func finish(_ result: Status, received: Bool, clearText: Bool = false) {
        keepAlive.stop()
        status = result
        canShowReceived = received
        if case .success = result, !received {
            if clearText {
                textToSend = ""
            } else {
                selectedFiles.forEach { try? FileManager.default.removeItem(at: $0) }
                selectedFiles.removeAll()
            }
            regenerateCode()
        } else if case .notice = result {
            regenerateCode()
        }
    }
}
