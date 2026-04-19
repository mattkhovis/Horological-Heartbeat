import SwiftUI
import AppKit

@main
struct HorologicalHeartbeatApp: App {
    @StateObject private var timeEngine  = TimeEngine()
    @StateObject private var menuBar     = MenuBarController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timeEngine)
                .onAppear {
                    timeEngine.start()
                    menuBar.start(engine: timeEngine)
                }
                .onDisappear {
                    timeEngine.stop()
                    menuBar.stop()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 560)
    }
}
