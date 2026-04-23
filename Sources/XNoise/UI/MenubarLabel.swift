import SwiftUI

struct MenubarLabel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if case .playing = model.audio.state {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative)
        } else {
            Image(systemName: "waveform")
        }
    }
}
