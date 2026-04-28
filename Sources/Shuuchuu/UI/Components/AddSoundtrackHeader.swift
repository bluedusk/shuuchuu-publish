import SwiftUI

/// Inline paste-a-link header that replaces the Soundtracks section header strip
/// while active. Visual peer of `SaveMixHeader`.
struct AddSoundtrackHeader: View {
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var model: AppModel

    let onCommit: () -> Void
    let onCancel: () -> Void

    @State private var rawText: String = ""
    @State private var validation: Validation = .empty
    @FocusState private var inputFocused: Bool

    private enum Validation: Equatable {
        case empty
        case ok(label: String)
        case unsupported
        case invalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                input
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
                Button("Add", action: commit)
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(addBackground)
                    .foregroundStyle(canAdd ? Color.white : Color.white.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .keyboardShortcut(.return, modifiers: [])
            }
            subText
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(design.accent.opacity(0.06))
        .onAppear { inputFocused = true }
    }

    private var input: some View {
        TextField("Paste a YouTube or Spotify URL", text: $rawText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(design.accent.opacity(0.7), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.18))
                    )
            )
            .focused($inputFocused)
            .onChange(of: rawText) { _, _ in revalidate() }
            .onSubmit(commit)
    }

    @ViewBuilder
    private var subText: some View {
        switch validation {
        case .empty:
            EmptyView()
        case .ok(let label):
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.leading, 4)
        case .unsupported:
            Text("Only YouTube and Spotify are supported in this version")
                .font(.system(size: 10))
                .foregroundStyle(design.accent)
                .padding(.leading, 4)
        case .invalid:
            EmptyView()
        }
    }

    private var addBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(canAdd ? design.accent : Color.white.opacity(0.08))
    }

    private var canAdd: Bool { if case .ok = validation { return true } else { return false } }

    private func revalidate() {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { validation = .empty; return }
        switch SoundtrackURL.parse(trimmed) {
        case .success(let parsed):       validation = .ok(label: parsed.humanLabel)
        case .failure(.unsupportedHost): validation = .unsupported
        case .failure(.invalidURL):      validation = .invalid
        }
    }

    private func commit() {
        guard canAdd else { return }
        let result = model.addSoundtrack(rawURL: rawText)
        if case .success = result {
            rawText = ""
            onCommit()
        }
    }
}
