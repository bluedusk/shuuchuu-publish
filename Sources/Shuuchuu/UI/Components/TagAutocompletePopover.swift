import SwiftUI

/// Suggestion list for the inline tag input. Caller owns input state; this view
/// renders matches and emits `onPick` when the user taps one.
struct TagAutocompletePopover: View {
    let suggestions: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(5), id: \.self) { tag in
                Button(action: { onPick(tag) }) {
                    Text(tag)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 120, maxWidth: 200)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Filters `pool` by case-insensitive prefix match against `query`,
    /// excluding any tag in `exclude`. Caps at 5 results.
    static func suggestions(query: String, pool: [String], exclude: Set<String>) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return pool
            .filter { !exclude.contains($0) && $0.hasPrefix(q) }
            .prefix(5)
            .map { $0 }
    }
}
