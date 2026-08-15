# SDD ledger — plan: Docs/superpowers/plans/2026-08-10-build17-security-hardening.md

Branch start: 290ae7b
Task 1: fix round 1/5 (4 addressed, 1 open — real Keychain save still delete-before-add; commits 196373e..184a8a8)
Task 1: fix round 2/5 (1 addressed, 0 open — update-first Keychain persistence; commits 184a8a8..aa00654)
Task 1: complete (commits 290ae7b..aa00654, review clean; Quick Connect 16/16, Keychain 4/4, JellyfinAPITests 64/64)
Task 2: complete (commit aa00654..cf8dcd3, independent review PASS; 4 Important found and addressed; security+gateway 40/40 with 3 live skips, hostile/ignored/oversized+keep-alive 4/4)
Task 3: complete (commit cf8dcd3..f57841c, independent review PASS; 3 Important found/addressed; lifecycle 6/6, final 87/87)
Task 3A: complete (commit b674fd3..e2e65f4, independent review PASS; focused 79/79, HLS 16/16 clean log, scheduler resilience 36/36, builds iOS/tvOS)
Task 4: complete (commit e2e65f4..c01975b, independent review PASS; 5 review rounds addressed; Synthetic 40/40, fresh HLS/AVPlayer/routing 71/71, resilience 36/36, builds iOS/tvOS)
Task 5: complete (commit c01975b..a4d6d78, independent review PASS; structure and numeric review findings addressed; Matroska 43/43, combined native gate 87/87, builds iOS/tvOS)
Task 6: complete (commit a4d6d78..d2da81d after HMAC seam review; hostile diagnostics RED 25 tests/62 failures; focused playback 103/103, ImageCache 6/6, mutations, scans, xcodegen, iOS/tvOS builds)
Task 7: complete (commit d2da81d..2e78a9d; correlation/storage/schema/runner mutations killed; Swift 75/75, isolated-uv ScriptTests 20/20, scans/xcodegen/builds iOS+tvOS)
Task 7: review follow-up complete (single sample-buffer evidence session/source chain including trusted handoff, scenario-only app boundary, correlated Apple-native overlays; Swift 103/103, isolated-uv ScriptTests 24/24, 3 mutations, scans/xcodegen/builds iOS+tvOS)
Task 8: complete (commit 87aa2b3; independent rereview PASS; secure runner 16/16, ScriptTests 40/40, runtime pipeline status and Unicode canary probes green, iOS loader gate 9 expected credential skips/0 failures, tvOS 26.5 build)
Task 9: complete (commit `a711266`; bounded artwork transport/decode/disk/concurrency; final 27/27 ImageCache-focused tests in Task 11, with remote-corpus and live-renderer limits documented)
Task 10: complete (commit `f0da17e`; revisioned async cache-loader publication; exact raw lock/unlock and scoped warning scans clean, iOS/tvOS gates passed)
Task 11: complete (source gate `73eef49`; no-publication code gate PASS; 55/55 ScriptTests, focused A 160 pass + 6 live skips, focused B 129/129, publication 8/8, full iOS 1,269 + 10 classified skips, iPad 3/3, tvOS 18/18 + build; external credentials/Xcode 26.6/DSA/rotation blockers recorded separately)
