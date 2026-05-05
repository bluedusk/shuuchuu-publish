# LemonSqueezy operationalisation

**Status:** Deferred. Code path implemented; not yet wired to live LS account or distribution-ready signing.
**Owner:** Unassigned.

## Context

The license/paywall code landed in this session per the spec at `docs/superpowers/specs/2026-05-03-lemonsqueezy-paywall-design.md`. That includes:

- `Sources/Shuuchuu/License/` — `LicenseState`, `LicenseStorage` (Keychain + file + in-memory backends), `LemonSqueezyClient`, `LicenseController`.
- `Sources/Shuuchuu/UI/Pages/LockedView.swift`, `Sources/Shuuchuu/UI/Components/LicenseSettingsBlock.swift`, lock glyph in `MenubarLabel`, trial-end pill in `FocusPage`.
- `AppModel.isLicensed` gate on every user-action method that produces audio/playback/persistence.
- `Tests/ShuuchuuTests/` — `LicenseStateTests`, `LicenseControllerTests`, `AppModelGatingTests`, `LicenseTestHelpers`.

The Swift implementation is complete. What is *not* done is everything required to actually charge money.

## What needs to happen before this can ship

1. **Create the LemonSqueezy product.**
   - Sign up at lemonsqueezy.com if not already.
   - Create a one-time-purchase product with license-key delivery enabled.
   - Set `activation_limit = 3` on the product/variant.
   - Capture the variant ID and replace `<variant-id>` placeholder in `Constants.swift` (`Constants.License.storeURL`).

2. **End-to-end test against the live LS API.**
   - The client is written against the documented `/v1/licenses/activate | validate | deactivate` endpoints. It has not been exercised against real responses.
   - Generate a test license key in the LS dashboard. Activate from the app. Confirm `LicenseController.state` transitions to `.licensed`. Verify the response shape matches the parser in `LemonSqueezyClient`.
   - Hit the activation-limit case (activate from a 4th machine): confirm `LSError.activationLimitReached` surfaces and the activation-sheet copy is correct.
   - Refund the test license in LS dashboard, relaunch the app: confirm `revalidate()` flips state to `.revoked(.disabled)` (or whichever status LS returns for refunds — verify it's actually `disabled` and not something else).

3. **Codesign for distribution.**
   - Current `scripts/run` uses a self-signed dev cert ("Shuuchuu Dev Signing Cert"). Gatekeeper will block this on any Mac other than the developer's own.
   - Switch to **Developer ID Application** signing for release builds. The `Developer ID Application: Dan Zhu (2X2Z855A2R)` identity already exists in the keychain.
   - Wire a release script that signs with that identity and notarises via `notarytool`.
   - Once signed with a stable Developer ID, the file-based fallback (`FileLicenseBackend`) is no longer needed — production should use `KeychainLicenseBackend` exclusively (already the dev default).

4. **Trial timer wall-clock vs activity time.**
   - Current implementation counts wall-clock time from first launch. A user who installs and never opens the app for 4 days has only 1 day of "real" trial.
   - Decide whether this is acceptable or whether trial should pause when the app isn't running. Spec chose wall-clock for simplicity; revisit only if conversion data suggests it's a problem.

5. **Refunds vs revocation copy.**
   - The current revoked-state messaging differentiates `.disabled / .expired / .refunded` but `revalidate()` only ever produces `.disabled` or `.expired` from LS responses (LS doesn't distinguish "refunded" in the license status). Either drop `.refunded` from `RevokeReason` or add explicit detection.

## Out of scope (intentional)

- Magic-link activation, custom URL scheme.
- License-recovery flow ("I lost my key").
- Receipts / invoices in-app.
- Webhook handler — soft revalidate-on-launch is the chosen primary signal.
- Educational discounts, family plans, gift codes.
- Mac App Store distribution (uses StoreKit, incompatible with the LemonSqueezy model).
