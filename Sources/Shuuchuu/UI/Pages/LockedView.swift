import SwiftUI
import AppKit

/// Replaces FocusPage when entitlement is locked. Two modes:
/// - intro:    headline + "Buy" / "Enter license key" buttons
/// - activate: paste-key form
struct LockedView: View {
    @EnvironmentObject var design: DesignSettings
    @EnvironmentObject var license: LicenseController

    enum Mode { case intro, activate }
    @State private var mode: Mode = .intro
    @State private var keyInput: String = ""
    @State private var activating = false
    @State private var inlineError: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            logo
            Spacer().frame(height: 18)
            headline
            Spacer().frame(height: 6)
            subline
            Spacer().frame(height: 28)
            switch mode {
            case .intro:    introButtons
            case .activate: activationForm
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header pieces

    private var logo: some View {
        Text("集中")
            .font(.system(size: 32, weight: .light))
            .foregroundStyle(design.accent)
            .opacity(0.92)
    }

    private var headline: some View {
        Text(headlineString)
            .font(.system(size: 17, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subline: some View {
        Text(sublineString)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headlineString: String {
        switch license.state {
        case .trialExpired:               return "Your 5-day trial has ended."
        case .revoked(.disabled):         return "This license is no longer active."
        case .revoked(.expired):          return "This license has expired."
        case .revoked(.refunded):         return "This license was refunded."
        default:                          return "Shuuchuu is locked."
        }
    }

    private var sublineString: String {
        switch license.state {
        case .revoked(.disabled), .revoked(.refunded):
            return "Buy a new license to continue, or contact support if this is unexpected."
        case .revoked(.expired):
            return "Buy a new license to continue."
        default:
            return "Buy a license to keep using Shuuchuu."
        }
    }

    // MARK: - Intro buttons

    private var introButtons: some View {
        VStack(spacing: 10) {
            Button {
                NSWorkspace.shared.open(Constants.License.storeURL)
            } label: {
                buttonLabel("Buy Shuuchuu", filled: true)
            }
            .buttonStyle(.plain)

            Button {
                inlineError = nil
                mode = .activate
            } label: {
                buttonLabel("Enter license key", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Activation form

    private var activationForm: some View {
        VStack(spacing: 10) {
            TextField("XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .disableAutocorrection(true)
                .onChange(of: keyInput) { _, _ in inlineError = nil }

            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { Task { await activate() } } label: {
                HStack(spacing: 6) {
                    if activating {
                        ProgressView().controlSize(.small)
                    }
                    Text(activating ? "Activating…" : "Activate")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(design.accent)
                        .opacity(canSubmit ? 1.0 : 0.35)
                )
                .foregroundStyle(.white)
                .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            Button {
                mode = .intro
                inlineError = nil
            } label: {
                Text("Back")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
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
            mode = .intro
            inlineError = nil
        } else {
            inlineError = LockedView.message(for: license.lastActivationError)
        }
    }

    static func message(for err: LSError?) -> String {
        switch err {
        case .network:
            return "Couldn't reach the license server. Check your connection and try again."
        case .licenseNotFound:
            return "We couldn't find that license. Double-check the key from your purchase email."
        case .activationLimitReached:
            return "This license is already on 3 Macs. Sign out from one in its Shuuchuu Settings, then try again."
        case .licenseDisabled:
            return "This license is no longer active. Contact support if this is unexpected."
        case .licenseExpired:
            return "This license has expired."
        case .alreadyActivatedOnThisMachine:
            return "This license is already active on this Mac."
        case .server, .malformedResponse, .none:
            return "Activation failed. Please try again."
        }
    }

    // MARK: - Button label helper

    @ViewBuilder
    private func buttonLabel(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(filled ? AnyShapeStyle(design.accent) : AnyShapeStyle(Color.white.opacity(0.10)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.white.opacity(filled ? 0 : 0.18), lineWidth: 1)
                    )
            )
            .foregroundStyle(filled ? .white : .primary)
    }
}
