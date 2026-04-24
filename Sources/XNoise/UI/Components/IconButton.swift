import SwiftUI

/// Small circular glass icon button used across the popover (back, settings, transport controls).
struct IconButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void
    @EnvironmentObject var design: DesignSettings

    init(systemName: String, size: CGFloat = 28, action: @escaping () -> Void) {
        self.systemName = systemName
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(
                    ZStack {
                        Rectangle().fill(.thinMaterial)
                        Color.white.opacity(0.10)
                    }
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
