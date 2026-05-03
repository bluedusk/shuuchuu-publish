import SwiftUI

/// Inline tag editor for a single soundtrack. Shown inside the active row's
/// expanded view (below the iframe). Renders chips with `×` removal and a
/// `+ add` chip that becomes a text field with autocomplete.
struct TagEditorStrip: View {
    let tags: [String]
    let pool: [String]                  // for autocomplete (library-wide tagsInUse)
    let onChange: ([String]) -> Void

    @EnvironmentObject var design: DesignSettings
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var atCap: Bool { tags.count >= TagNormalize.maxTagsPerSoundtrack }

    private var suggestions: [String] {
        TagAutocompletePopover.suggestions(
            query: draft,
            pool: pool,
            exclude: Set(tags)
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Tags")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.45))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        chip(tag)
                    }
                    if editing {
                        inputField
                    } else {
                        addChip
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func chip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.75))
            Button(action: { remove(tag) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .transition(.opacity)
    }

    private var addChip: some View {
        Button(action: beginEditing) {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                Text("add").font(.system(size: 10))
            }
            .foregroundStyle(Color.white.opacity(atCap ? 0.22 : 0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                Capsule()
                    .strokeBorder(
                        Color.white.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(atCap)
        .help(atCap ? "Up to 3 tags" : "")
    }

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.white)
                .frame(width: 80)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(design.accent, lineWidth: 1))
                .focused($inputFocused)
                .onSubmit(commit)
                .onExitCommand { cancelEditing() }
                .onKeyPress(.tab) {
                    if let top = suggestions.first {
                        draft = top
                        commit()
                        return .handled
                    }
                    return .ignored
                }
                .onChange(of: inputFocused) { _, focused in
                    if !focused { commit() }
                }

            if !suggestions.isEmpty {
                TagAutocompletePopover(
                    suggestions: suggestions,
                    onPick: { pick in
                        draft = pick
                        commit()
                    }
                )
            }
        }
    }

    private func beginEditing() {
        guard !atCap else { return }
        draft = ""
        editing = true
        DispatchQueue.main.async { inputFocused = true }
    }

    private func commit() {
        guard editing else { return }
        defer { cancelEditing() }
        guard let n = TagNormalize.normalize(draft), !tags.contains(n) else { return }
        guard !atCap else { return }
        onChange(tags + [n])
    }

    private func cancelEditing() {
        editing = false
        draft = ""
    }

    private func remove(_ tag: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            onChange(tags.filter { $0 != tag })
        }
    }
}
