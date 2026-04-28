import SwiftUI

/// Small circular glass icon button used across the popover.
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
