import Foundation

/// Holds app state and runs transfers. Heavy work runs on a background task;
/// UI-facing state is only touched on the main actor.
@MainActor
final class TransferModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case working(String)
        case success(String)
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
    @Published var relay: String = CrocBridge.defaultRelay
    @Published var relayPassword: String = ""

    /// Received files are saved here and appear under "On My iPhone > Croc" in the Files app.
    var receiveFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Received", isDirectory: true)
    }

    init() {
        regenerateCode()
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
        status = .working("Waiting for the receiver to enter the code…")

        Task.detached(priority: .userInitiated) {
            do {
                try CrocBridge.send(files: files, code: code, relay: relayAddress, relayPassword: password)
                await self.finish(.success("Sent \(files.count) item(s)."))
            } catch {
                await self.finish(.failure(error.localizedDescription))
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
        status = .working("Connecting to sender…")

        Task.detached(priority: .userInitiated) {
            do {
                try CrocBridge.receive(code: code, relay: relayAddress, relayPassword: password, destination: destination)
                await self.finish(.success("Files saved. Open the Files app → Croc → Received."))
            } catch {
                await self.finish(.failure(error.localizedDescription))
            }
        }
    }

    func clearStatus() {
        if !status.isWorking { status = .idle }
    }

    private func finish(_ result: Status) {
        status = result
        if case .success = result {
            selectedFiles.forEach { try? FileManager.default.removeItem(at: $0) }
            selectedFiles.removeAll()
            regenerateCode()
        }
    }
}
