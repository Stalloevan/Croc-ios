import SwiftUI

@main
struct CrocAppMain: App {
    @StateObject private var model = TransferModel()
    @StateObject private var ssh = SSHController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(ssh)
        }
    }
}
