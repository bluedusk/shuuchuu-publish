# Phantom sound on startup — playing audio not in the mix list

**Reported:** 2026-04-25

## Symptom

On launch, audio plays that does **not** correspond to any track shown in the current mix. The mix list (chips at the top of the popover) doesn't include whatever is making sound — so it's not just a "previous mix auto-resumed" issue. The audio source is invisible to the UI.

## Hypothesis

Something in the audio pipeline is producing output without being tracked by `MixingController.live`. Candidates:

- A `NoiseSource` / `AVAudioPlayerNode` from a prior run that's being attached + started but never registered in the `live` dict the UI reads.
- The persisted mix snapshot (`x-noise.savedMix` in `UserDefaults`) restores track playback through a path that bypasses the UI's source of truth — e.g., calling `MixingController.addOrUpdate` without updating `live`, or restoring before `live` is wired up.
- A procedural source (white/pink/brown/green/fluorescent) that's being instantiated and started by the restore but its track id isn't being inserted into `live` because of a key mismatch.
- `AVAudioEngine` being started with a node still attached from a previous configuration.

## Where to look

- `AppModel` init / mix-restore path — confirm restored tracks appear in `mixer.live`.
- `MixingController.addOrUpdate` and the `live: [TrackID: …]` dictionary — verify every started player node has a matching entry.
- `persistMix()` / restore symmetry — what exactly is being snapshotted vs. restored.
- Procedural sources especially — `ProceduralNoiseSource` uses `AVAudioSourceNode` which produces audio as soon as the engine runs, regardless of UI state.

## Repro

1. Launch (`swift run`).
2. Sound plays immediately even though the mix chip row appears empty (or shows tracks that don't match what's audible).

## Expected

Either nothing should play on launch, or only tracks visible in the mix list should play. The audible state must always be reflected by `mixer.live`.
