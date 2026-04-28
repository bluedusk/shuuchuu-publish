---
title: Releasing
aliases:
  - Release
  - Release Process
tags:
  - type/guide
  - topic/packaging
  - status/current
---

# Releasing

## Release Process

### Step 1: Ask Claude to prepare the release

Tell Claude: "let's release 0.2.0" (or whatever version).

Claude will:

1. Gather all commits since the last tag
2. Draft a changelog and present it for review
3. Categorize changes into: **New**, **Fixed**, **Improved**

### Step 2: Review the changelog together

Discuss what to include. Not everything needs to be in the changelog:

**Show to users:**
- New features they can use
- Bug fixes they'll notice
- UX improvements

**Don't show to users:**
- Internal refactors
- CI/build changes
- Code cleanup
- Developer tooling changes

Claude updates `CHANGELOG.md` with the approved entries.

### Step 3: Run the release

```bash
# Stable release — goes to all users
./scripts/release.sh 0.2.0

# Beta release — only reaches users who opted in via Settings > Beta Updates
./scripts/release.sh --beta 0.2.0-beta.1

# Skip confirmation prompts
./scripts/release.sh -y 0.2.0
```

All releases must be run from main branch.

## What the Script Does (6 Steps)

1. **Build & Package** — `package-app.sh` builds a release binary, assembles the `.app` bundle, signs, notarizes, creates DMG + ZIP
2. **Update appcast.xml** — Adds a new `<item>` with EdDSA signature. Beta adds `sparkle:channel="beta"` attribute.
3. **Stamp changelog** — Moves `[Unreleased]` to `[version] - date` in `CHANGELOG.md`
4. **Commit & tag** — Commits appcast + changelog, creates `vX.Y.Z` tag. Beta pushes only the tag (not main). Stable pushes main + tag.
5. **GitHub Release + round-trip verify** — Creates release on `bluedusk/x-noise` with DMG + ZIP, then `gh release download`s the DMG back from GitHub and asserts its SHA-256 matches the local upload. The downloaded SHA becomes the source of truth for step 6.
6. **Deploy appcast** — Pushes `appcast.xml` to `shuuchuu.app` website repo, deploys via `pnpm ship`. Skipped for beta (Sparkle reads it directly from the site).

The release is not "done" until step 6 passes. There are no manual post-release checks to remember.

> **No Homebrew tap** — Shuuchuu is a menubar utility that requires macOS 26+. Until macOS 26 ships publicly, Homebrew is deferred.

## Stable vs Beta

The app uses Sparkle's built-in channel system. Both stable and beta releases share a single `appcast.xml`.

| | Stable | Beta |
|--|--------|------|
| Version format | `X.Y.Z` (e.g. `0.2.0`) | `X.Y.Z-beta.N` (e.g. `0.2.0-beta.1`) |
| Sparkle channel | No channel attribute (everyone sees it) | `sparkle:channel="beta"` (opt-in only) |
| GitHub Release | Full release | Pre-release |
| Website download | Available via `/latest/` redirect | Not available (beta users get updates via Sparkle) |
| Push to main | Commit + tag | Tag only |

**User opt-in:** Settings > Beta Updates toggle (stored as `UserDefaults` key `app.betaUpdates`). `UpdateChecker.allowedChannels(for:)` returns `["beta"]` or `[]` based on the toggle. Beta users still receive stable updates — Sparkle shows whichever is newer.

## If a step fails

DMGs are not byte-deterministic — re-running `package-app.sh` produces a DMG with the same content but a different SHA-256 (HFS metadata, timestamps, code-sign blob differ). The script protects against this with one invariant:

- **Step 5 always uses the SHA of the DMG GitHub actually serves**, derived from the round-trip download. So even if you re-run after a packaging change, the appcast SHA stays in sync with the published asset.

Recovery rules:

- **Steps 1–4 failed** (build, appcast, changelog, commit/tag): safe to re-run from scratch. Nothing user-visible has shipped yet. If a tag was already pushed, delete it (`git push --delete origin vX.Y.Z` + `git tag -d vX.Y.Z`) before re-running.
- **Step 5 failed** (GitHub release or round-trip verify): if the round-trip SHA mismatch fired, the release is corrupt — delete the release (`gh release delete vX.Y.Z --repo bluedusk/x-noise --yes --cleanup-tag`) and re-run from step 1.
- **Step 6 failed** (appcast deploy): re-run only step 6 (`pnpm ship` from the web repo, or re-invoke the gh-api PUT block from `release.sh`).

## Website (shuuchuu.app)

The website lives in `~/playground/x-noise-web` (Astro, deployed to Cloudflare Pages via `pnpm ship`).

**Download links:**
- **Hero download button**: Uses `https://github.com/bluedusk/x-noise/releases/latest/download/Shuuchuu.dmg` — GitHub's `/latest/` redirect automatically resolves to the newest **non-pre-release**, so beta releases are excluded without any website changes.

**For stable releases:** Redeploy the site so the version badge updates. This is part of the release — do it in the same session as `release.sh`.

**For beta releases:** No website changes needed.

## What Users See

When a user launches Shuuchuu and a new version is available, Sparkle shows an update window with:
- What's new (features)
- What's fixed (bugs)
- What's improved (UX)
- Install / Skip / Remind Me Later buttons

## Prerequisites

All one-time setup. Once done, only `.env` and your Keychain are needed.

### .env

The script reads secrets from `.env` in the repo root (gitignored):

```
SHUUCHUU_SIGN_IDENTITY="Developer ID Application: Dan Zhu (2X2Z855A2R)"
SHUUCHUU_NOTARY_PROFILE=shuuchuu-notary
SPARKLE_EDDSA_KEY=<your-sparkle-private-key>
SPARKLE_EDDSA_PUBLIC_KEY=<your-sparkle-public-key>
```

### Signing certificate

Developer ID Application certificate must be in your Keychain. Verify:

```bash
security find-identity -v -p codesigning | grep "Developer ID"
```

### Notary credentials

Stored in Keychain via:

```bash
xcrun notarytool store-credentials "shuuchuu-notary" \
  --apple-id <your-email> \
  --team-id 2X2Z855A2R \
  --password <app-specific-password>
```

### Sparkle EdDSA key

Generated once with `.build/artifacts/sparkle/Sparkle/bin/generate_keys`. Private key lives in Keychain and in `.env`. Public key is embedded in the app via `SUPublicEDKey` in `package-app.sh`.

Sparkle must be added to `Package.swift` as a binary target (`.binaryTarget` pointing to the Sparkle XCFramework release artifact) before the first release.

### Tools

- `gh` CLI (authenticated)
- `create-dmg` (`brew install create-dmg`)
- Xcode command line tools

## Versioning

[Semantic Versioning](https://semver.org/):

- **Patch** (0.1.x): bug fixes, small improvements
- **Minor** (0.x.0): new features
- **Major** (x.0.0): breaking changes

## Assets

| File | Purpose |
|------|---------|
| `Shuuchuu.dmg` | Styled disk image for users |
| `Shuuchuu.zip` | Plain zip for Sparkle auto-update |

## Architecture

- **Release repo:** `bluedusk/x-noise` (public, GitHub releases)
- **Development repo:** local / private
- **Website repo:** `~/playground/x-noise-web` (Astro, Cloudflare Pages at shuuchuu.app)
- **Appcast URL:** `https://shuuchuu.app/appcast.xml`
- **Download URLs:** `https://github.com/bluedusk/x-noise/releases/download/vX.Y.Z/Shuuchuu.dmg`

## Infrastructure TODOs

These need to be set up before the first release:

- [ ] Create `bluedusk/x-noise` GitHub repo
- [ ] Add Sparkle as a binary dependency in `Package.swift`
- [ ] Write `scripts/package-app.sh` (build release binary, assemble `.app`, sign, notarize, create DMG + ZIP)
- [ ] Write `scripts/release.sh` (orchestrate all 6 steps)
- [ ] Create `CHANGELOG.md` with `[Unreleased]` section
- [ ] Create `appcast.xml` (empty, first release will populate it)
- [ ] Create the `shuuchuu.app` website and deploy pipeline
- [ ] Generate Sparkle EdDSA key pair and store in Keychain + `.env`
- [ ] Obtain Developer ID certificate and set up notary credentials
