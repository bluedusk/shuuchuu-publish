import SwiftUI

/// Inline header that replaces the Sounds-page header during save mode. Two sub-states
/// per `AppModel.saveMode`:
///   - .naming(text:): text field + Cancel + Save + live preview row showing current mix.
///   - .confirmingOverwrite(text:existing:): "Overwrite "X"?" + [Save as new] [Overwrite].
struct SaveMixHeader: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var state: MixState
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch model.saveMode {
            case .naming(let text):
                namingHeader(text: text)
                previewRow
            case .confirmingOverwrite(let text, let existing):
                confirmHeader(text: text, existing: existing)
            case .inactive:
                EmptyView()
            }
        }
        .background(design.accent.opacity(0.06))
    }

    private func namingHeader(text: String) -> some View {
        HStack(spacing: 8) {
            TextField("Name this mix…", text: Binding(
                get: { text },
                set: { model.updateSaveName($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(design.accent.opacity(0.45), lineWidth: 1)
            )
            .focused($nameFocused)
            .onSubmit { model.commitSaveMix() }
            .onAppear { nameFocused = true }

            Button("Cancel") { model.cancelSaveMix() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .xnText(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .keyboardShortcut(.cancelAction)

            Button(action: { model.commitSaveMix() }) {
                Text("Save")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(design.accent.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var previewRow: some View {
        HStack(spacing: 6) {
            Text("SAVING")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .xnText(.secondary)
            Text(previewText)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var previewText: String {
        let names = state.tracks.compactMap { model.findTrack(id: $0.id)?.name }
        return names.joined(separator: " · ")
    }

    private func confirmHeader(text: String, existing: SavedMix) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Overwrite \"\(existing.name)\"?")
                .font(.system(size: 12, weight: .medium))
                .xnText(.primary)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button("Save as new") { model.saveAsNewWithSuffix() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .xnText(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                Button(action: { model.overwriteExisting() }) {
                    Text("Overwrite")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(design.accent.opacity(0.85))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
