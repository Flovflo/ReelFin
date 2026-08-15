# HEVC HLS manifest compatibility implementation plan

**Goal:** Make synthetic HEVC HLS variants truthfully describe their source so AVPlayer accepts SDR Main 10 and HDR content.

**Scope:** `DolbyVisionGate`, a focused HEVC codec-string helper, `SyntheticHLSSession` only if wiring requires it, and focused NativeBridge/HLS tests. Do not change loopback authorization, segment generation policy, or Jellyfin state.

## Task 1: RED for truthful HEVC signaling

- Add focused tests using distinct `hvcC` records whose profile, compatibility, tier, level, and constraint bytes differ from the old constant.
- Prove current output hardcodes `hvc1.2.4.L153.B0`.
- Prove a Main 10 source with explicit SDR metadata currently emits `VIDEO-RANGE=PQ`.
- Add malformed/truncated `hvcC` cases that must not emit a fabricated fully qualified codec.

## Task 2: Minimal checked projection

- Implement one checked `hvcC` to RFC 6381/ISO Annex E projection.
- Use the effective sample entry prefix and parsed source fields in `evaluatePackaging`.
- Remove Main 10-only PQ inference; retain explicit PQ/HLG/DV/HDR10 evidence.
- Make the playback expectation SDR when the effective HEVC range is SDR.

## Task 3: GREEN and mutation proof

- Run packaging decision, FMP4 repackager, manifest builder, synthetic HLS, and variant selector tests.
- Mutate the codec back to the constant; the alternate-profile test must fail.
- Restore Main 10-only PQ inference; the SDR test must fail.
- Accept truncated `hvcC`; the malformed-input test must fail.

## Task 4: AVPlayer compatibility gate

- Generate a real HEVC Main 10 SDR fixture.
- Require playlist request, init request, media request, `isPlayable`, `readyToPlay`, progression, effective seek, detach, and replay on iPhone 17 / iOS 26.5.
- Add a PQ signaling control and retain H.264 real-playback coverage.
- Run the HLS and playback-resilience gates, update `OPTIMIZATION_AUDIT.md`, review the exact diff, and commit `fix: derive HEVC HLS signaling`.
