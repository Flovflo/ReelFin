# Task 8 Report — uv-only, secret-safe QA execution

Date: 2026-08-12

## Outcome

The QA entry points now fail closed on the fixed ReelFin uv installation and its canonical managed Python 3.13 interpreter. Credentialed commands receive only their exact ephemeral environment; aliases are unset before work begins. Runtime and xcodebuild stdout/stderr are redacted before persistence, retained text is scanned without echoing matches, and DerivedData, scenario/resume state, and implicit result bundles live only in owner-only temporary directories removed by one immutable exit/signal trap.

## Acceptance ledger

| Gate | Evidence | Result |
| --- | --- | --- |
| RED | The pre-correction secure-runner class produced 15 assertion failures across 11 tests, exposing wrapper isolation, encoding, pipeline, retention, and cleanup gaps. | PASS |
| uv boundary | Fixed uv/install/cache paths; offline, no-project, no-config, no-env-file, no-download, managed-Python execution; canonical path and Python 3.13 identity checks. | PASS |
| Secret ingress/scope | Password accepted only from the already-present ephemeral environment or stdin; credential keys rejected in env files; non-exported locals are unset from inherited aliases and passed through child-specific `env -i` commands. | PASS |
| Artifact lifecycle | Owner-only `mktemp` roots hold DerivedData, resume/scenario state, and implicit `.xcresult`; the sole trap scans-or-deletes persisted logs and removes temporary state on normal exit and signals. | PASS |
| Redaction/scanning | Both output streams pass through redaction before `tee`; raw UTF-8 Unicode plus exact upper/lower/mixed percent-encoded forms are covered; canaries travel through env/stdin, never argv. | PASS |
| Failure propagation | Foreground and background-runtime producer, redactor, and tee statuses are captured under `set +e`, read after shutdown, and independently propagated before success. | PASS |
| Mutation | Removing each of six uv flags failed; injected foreground statuses 23/24/25 failed; ignoring background redactor status 24 failed both runner harnesses; removing the raw Unicode candidate leaked `päss-✓` and failed; raw tee ordering, direct `python3`, executable helper metadata, and retained canaries also failed before restoration. | PASS |
| Script regression | `scripts/run_python_with_uv.sh -m unittest discover -s Tests/ScriptTests -p 'test_*.py'`: 40 tests, 0 failures. | PASS |
| Project/build gates | `xcodegen generate` passed; focused ReelFin iOS 26.5 tests passed with eight expected credential skips; ReelFinTV tvOS 26.5 build passed. | PASS |
| Scope | No live Jellyfin run, network publication, push, or release mutation. Task 7's scenario-only four Swift environment loaders remain unchanged. Generated scheme-only noise was restored. | PASS |

## Residual note

The credential-gated Swift selections intentionally skipped because this task forbids live credentials. Their compile/load paths and skip behavior passed; authenticated playback remains a separate opt-in gate.
This scripts-only rereview did not alter Swift, project, or build configuration, so the recorded iOS/tvOS 26.5 gates remain the proportionate build evidence.
