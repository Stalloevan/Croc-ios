import SwiftUI

@main
struct CrocAppMain: App {
    @StateObject private var model = TransferModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
