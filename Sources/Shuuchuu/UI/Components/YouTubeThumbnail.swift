import SwiftUI

/// Square YouTube thumbnail crop loaded from img.youtube.com. Falls back to a
/// red play-glyph placeholder if the image fails to load (offline, gone video).
struct YouTubeThumbnail: View {
    let url: URL
    let size: CGFloat
    let cornerRadius: CGFloat

    init(url: URL, size: CGFloat, cornerRadius: CGFloat = 6) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .empty, .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        let tint = Color(red: 1.00, green: 0.00, blue: 0.00)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay(
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}
