import SwiftUI

/// User-facing tweaks panel — accent hue, wallpaper, theme, glass blur/opacity/stroke.
/// Mirrors the design bundle's TweaksPanel 1:1.
struct TweaksPanel: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var design: DesignSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appearance
                    glass
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
        }
        .frame(width: 300, height: 520)
        .glassPanel(cornerRadius: 18, design: design)
    }

    private var header: some View {
        HStack {
            Text("x-noise tweaks")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Appearance")

            sliderRow(
                title: "Accent hue",
                value: Binding(get: { design.accentHue }, set: { design.accentHue = $0 }),
                range: 0...360, step: 1,
                display: { String(Int($0)) }
            )

            radioRow(title: "Wallpaper",
                     options: WallpaperMode.allCases,
                     label: { $0.display },
                     selection: Binding(get: { design.wallpaper }, set: { design.wallpaper = $0 }))

            radioRow(title: "Theme",
                     options: AppTheme.allCases,
                     label: { $0.rawValue },
                     selection: Binding(get: { design.theme }, set: { design.theme = $0 }))
        }
    }

    private var glass: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Glass")

            sliderRow(
                title: "Blur",
                value: Binding(get: { design.glassBlur }, set: { design.glassBlur = $0 }),
                range: 4...60, step: 1,
                display: { "\(Int($0))px" }
            )
            sliderRow(
                title: "Opacity",
                value: Binding(get: { design.glassOpacity }, set: { design.glassOpacity = $0 }),
                range: 0.04...0.5, step: 0.01,
                display: { String(format: "%.2f", $0) }
            )
            sliderRow(
                title: "Stroke",
                value: Binding(get: { design.glassStroke }, set: { design.glassStroke = $0 }),
                range: 0...0.6, step: 0.01,
                display: { String(format: "%.2f", $0) }
            )
        }
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 10, weight: .medium))
            .kerning(1.2)
            .foregroundStyle(.secondary)
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(design.accent)
        }
    }

    private func radioRow<Opt: Hashable>(
        title: String,
        options: [Opt],
        label: @escaping (Opt) -> String,
        selection: Binding<Opt>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13))
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { opt in
                    Button(label(opt).capitalized) { selection.wrappedValue = opt }
                        .font(.system(size: 11.5, weight: selection.wrappedValue == opt ? .semibold : .regular))
                        .foregroundStyle(selection.wrappedValue == opt ? Color.primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection.wrappedValue == opt ? Color.white.opacity(0.18) : Color.clear)
                        )
                        .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
    }
}
