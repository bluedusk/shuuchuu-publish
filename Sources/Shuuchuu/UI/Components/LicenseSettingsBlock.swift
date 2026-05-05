import SwiftUI
import AppKit

/// License section content for SettingsPage. State-dependent rendering:
/// - Trial: "N days remaining" + Enter key
/// - Licensed: masked key + Sign out
/// - Locked / Revoked: status line + Enter key
struct LicenseSettingsBlock: View {
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var license: LicenseController

    @State private var showActivation = false
    @State private var keyInput = ""
    @State private var activating = false
    @State private var inlineError: String?
    @State private var confirmingSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch license.state {
            case .trial:                        trialBody
            case .licensed:                     licensedBody
            case .trialExpired, .revoked:       lockedBody
            case .uninitialized:                EmptyView()
            }
            if showActivation { activationForm }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Trial

    private var trialBody: some View {
        let days = license.trialDaysRemaining
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Trial")
                    .font(.system(size: 13, weight: .regular))
                Spacer()
                Text("\(days) day\(days == 1 ? "" : "s") remaining")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            actionButtons(includeBuy: true)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Licensed

    private var licensedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activated")
                    .font(.system(size: 13, weight: .regular))
                Spacer()
                Text(maskedKey)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let validated = lastValidated {
                Text("Last verified \(formatted(validated))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Spacer()
                if confirmingSignOut {
                    Text("Are you sure?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Cancel") { confirmingSignOut = false }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button {
                        confirmingSignOut = false
                        Task { await license.deactivateThisDevice() }
                    } label: {
                        Text("Sign out")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7).fill(Color.red.opacity(0.85))
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { confirmingSignOut = true } label: {
                        Text("Sign out of this Mac")
                            .font(.system(size: 11, weight: .regular))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Locked / revoked

    private var lockedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lockedHeadline)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
            actionButtons(includeBuy: true)
        }
        .padding(.vertical, 6)
    }

    private var lockedHeadline: String {
        switch license.state {
        case .trialExpired:           return "Trial ended."
        case .revoked(.disabled):     return "License inactive."
        case .revoked(.expired):      return "License expired."
        case .revoked(.refunded):     return "License refunded."
        default:                      return ""
        }
    }

    // MARK: - Activation form (collapsed)

    private var activationForm: some View {
        VStack(spacing: 8) {
            TextField("XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.20))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
                .disableAutocorrection(true)
                .onChange(of: keyInput) { _, _ in inlineError = nil }

            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") {
                    showActivation = false
                    keyInput = ""
                    inlineError = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await activate() } } label: {
                    HStack(spacing: 4) {
                        if activating { ProgressView().controlSize(.small) }
                        Text(activating ? "Activating…" : "Activate")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(design.accent)
                            .opacity(canSubmit ? 1.0 : 0.35)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(.top, 8)
    }

    private var canSubmit: Bool {
        !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !activating
    }

    private func activate() async {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activating = true
        defer { activating = false }
        let ok = await license.activate(key: trimmed)
        if ok {
            keyInput = ""
            showActivation = false
            inlineError = nil
        } else {
            inlineError = LockedView.message(for: license.lastActivationError)
        }
    }

    // MARK: - Action buttons

    private func actionButtons(includeBuy: Bool) -> some View {
        HStack {
            Spacer()
            if includeBuy {
                Button {
                    NSWorkspace.shared.open(Constants.License.storeURL)
                } label: {
                    Text("Buy")
                        .font(.system(size: 11, weight: .regular))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
            Button { showActivation.toggle() } label: {
                Text(showActivation ? "Hide" : "Enter license key")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(design.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var maskedKey: String {
        if case .licensed(let key, _, _) = license.state {
            let last4 = String(key.suffix(4))
            return "XXXX-…-\(last4)"
        }
        return ""
    }

    private var lastValidated: Date? {
        if case .licensed(_, _, let v) = license.state, v != .distantPast {
            return v
        }
        return nil
    }

    private func formatted(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
}
