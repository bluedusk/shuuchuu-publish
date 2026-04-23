import SwiftUI

@main
struct XNoiseApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("x-noise")
        } label: {
            Image(systemName: "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}
