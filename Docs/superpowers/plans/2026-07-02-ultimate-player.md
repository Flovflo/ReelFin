# Ultimate Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compléter le custom engine prouvé (ttff 3,4 s / 0 stall / réservoir 356 s) pour atteindre : démarrage perçu < 1 s, never-cut absolu (lane SDR dernier recours + retour DV auto), AirPlay/PiP corrects, sous-titres externes, skip/next, stats — puis basculer le custom player par défaut.

**Architecture:** Additif sur `PlaybackEngine/CustomPlayer/*` (aucun rebuild). Chaque capacité = policy PURE unit-testée + intégration moteur derrière le harness offline `ThrottledDropHTTPServer`. Le transcode SDR est résolu par appel scopé (jamais global — leçon écran-noir). La session cache DV reste vivante pendant la lane SDR pour l'upgrade-back.

**Tech Stack:** Swift 5.9, AVFoundation/AVKit, XCTest. Sim iPhone 16 Pro iOS 26.3 `3EC3A5CB-0DE2-4E8D-BAF1-6F97BDF49577`, `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, `xcodegen generate` après tout nouveau fichier.

## Global Constraints

- Apple-native uniquement (AVFoundation/AVKit) ; jamais de resource-loader custom pour le DV (N1).
- Le démarrage direct-play ne doit JAMAIS voir le transcode (résolution SDR scopée au fallback).
- HEVC stream-copy (`conservativeCompatibility`) interdit — SDR = H.264 tone-mappé serveur (N5).
- Un stall ne rebuild jamais l'item (N4) ; la lane SDR exige inability soutenue + réservoir vide.
- Tests: `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,id=3EC3A5CB-0DE2-4E8D-BAF1-6F97BDF49577' -only-testing:PlaybackEngineTests/<Suite>`

---

### Task 1: CustomPlayerPrewarmer (démarrage perçu < 1 s)

**Files:**
- Create: `PlaybackEngine/Sources/PlaybackEngine/CustomPlayer/CustomPlayerPrewarmer.swift`
- Modify: `PlaybackEngine/Sources/PlaybackEngine/CustomPlayer/CustomPlaybackEngine.swift` (adoption dans `runLoad`)
- Modify: `ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift` (`.task` prewarm + discard)
- Test: `Tests/PlaybackEngineTests/PlaybackDropResilienceTests.swift`

**Interfaces:**
- Produces: `@MainActor final class CustomPlayerPrewarmer { init(resolver: CustomPlaybackSourceResolving, store: MediaGatewayStore); func prewarm(itemID: String, startTimeTicks: Int64?); func consume(itemID: String) -> PrewarmedPlayback?; func discardIfUnused(); }` et `struct PrewarmedPlayback { let resolved: ResolvedOriginalSource; let session: CacheProxySession; let localURL: URL }`
- Consumes: `CacheProxySession.start()`, `ResolvedOriginalSource`.
- `CustomPlaybackEngine.init` gagne `prewarmer: CustomPlayerPrewarmer? = nil`; `runLoad` appelle `prewarmer?.consume(itemID:)` et saute résolution+start si hit (adopte session+localURL).

- [x] Test `testPrewarmedLoadStartsFromExistingSessionWithoutNewResolve` : resolver-mock compte ses appels ; prewarm → attendre réservoir ≥ 6 s → engine.load(même item) → phase .playing en < 3 s ET resolveCalls == 1.
- [x] Test `testPrewarmDiscardStopsSessionAndFreesServer` : prewarm → discardIfUnused() → `LocalCacheHTTPServer.debugActiveConnectionCount == 0` et un GET sur localURL échoue.
- [x] Implémentation minimale + branchement DetailView (`.task(id:)` sur l'item quand flag custom ON ; discard sur disparition sans lecture).
- [x] Suites vertes + commit `feat(custom-player): detail-view prewarm — perceived instant start`.

### Task 2: AdaptiveLanePolicy + lane SDR dernier recours avec retour DV

**Files:**
- Create: `PlaybackEngine/Sources/PlaybackEngine/CustomPlayer/AdaptiveLanePolicy.swift`
- Modify: `CustomPlaybackEngine.swift` (monitorTick → décisions lane ; swap items ; état `degradedSDR`)
- Modify: `JellyfinOriginalSourceResolver.swift` (+ `resolveAdaptiveFallback(itemID:) -> URL?` via PlaybackInfo EnableTranscoding scopé, profil H.264/TS AAC — jamais fMP4, jamais stream-copy)
- Test: Create `Tests/PlaybackEngineTests/AdaptiveLanePolicyTests.swift` (+ intégration dans PlaybackDropResilienceTests)

**Interfaces:**
- Produces (pure, Sendable): `enum AdaptiveLanePolicy { struct State; static func decision(now:, lane: Lane, buffering: Bool, sustainedBelowBitrateSeconds: Double, dvReservoirSeconds: Double, headroom: Double, state: inout State) -> LaneChange? }` avec `enum Lane { original, sdrFallback }`, `enum LaneChange { dropToSDR, returnToOriginal }`.
- Seuils: drop = sustainedBelow ≥ 90 s ET buffering ; return = headroom ≥ 1,3 soutenu 30 s ET dvReservoir ≥ 30 s ; anti-flap : cooldown 300 s, 2 échecs d'upgrade → verrou SDR.
- Consumes: `ConnectionMonitor.sustainedBelowBitrateSeconds/headroom` (déjà alimentés), `CacheProxySession.reservoirSecondsAhead`.
- Engine: `private func switchToSDRLane(url: URL)` / `private func returnToOriginalLane()` — replaceCurrentItem à currentTime, session DV JAMAIS stoppée pendant SDR ; `bufferingState.phase = .degradedSDR` pendant la lane SDR.

- [x] Tests policy (drop exige les DEUX conditions ; dip court ne droppe pas ; return exige hystérésis + réservoir ; anti-flap/cooldown ; verrou après 2 échecs).
- [x] Test intégration `testEngineDropsToSDRLaneAfterSustainedStarvationAndReturns` : origin throttlé 0,4× bitrate (annonce un sourceBitrate gonflé au resolver-mock) + un second endpoint HLS local minimal servi par le harness ; vérifier swap → .degradedSDR → accélérer le throttle à 3× → retour .playing original.
- [x] `resolveAdaptiveFallback` : test unitaire de construction de requête (client mock) — EnableDirectPlay=false/EnableTranscoding=true/h264/ts ; retour nil toléré (pas de lane si serveur sans transcode).
- [x] Suites vertes + commit `feat(custom-player): last-resort SDR lane with automatic DV return`.

### Task 3: AirPlay origin-swap + PiP-safe teardown

**Files:**
- Modify: `CustomPlaybackEngine.swift` (KVO `player.isExternalPlaybackActive` → swap origin/localhost à currentTime ; `allowsExternalPlayback = true` rétabli ; expose `var isPictureInPictureActive: Bool`)
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift` (delegate AVPlayerViewController → PiP flags ; onDisappear ne stop() plus si PiP actif)
- Test: PlaybackDropResilienceTests

**Interfaces:**
- Produces: `CustomPlaybackEngine.handleExternalPlaybackChange(active: Bool)` (internal, testable) ; `PrewarmedPlayback` inchangé.

- [x] Test `testExternalPlaybackSwapUsesOriginURLAndSwapsBackToLocalhost` : appeler handleExternalPlaybackChange(true/false) → asset.url.host passe de 127.0.0.1 à l'hôte origin puis revient ; currentTime préservé (tolérance 2 s).
- [x] PiP : vérif manuelle sim (pas de harness AVKit) — garde-fou logique unit-testé si extrait pur.
- [x] Suites vertes + commit `feat(custom-player): correct AirPlay (origin URL) + PiP-safe lifecycle`.

### Task 4: Sous-titres externes (overlay SRT)

**Files:**
- Create: `PlaybackEngine/Sources/PlaybackEngine/CustomPlayer/SubtitleOverlayModel.swift`
- Modify: `JellyfinOriginalSourceResolver.swift` (+ liste `ExternalSubtitleTrack {id,label,url,format}` depuis la MediaSource résolue)
- Modify: `CustomPlayerView.swift` (overlay texte + menu pistes), `CustomPlaybackEngine.swift` (periodic time observer publie `currentSubtitleCue`)
- Test: Create `Tests/PlaybackEngineTests/SubtitleOverlayModelTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class SubtitleOverlayModel { func load(track: ExternalSubtitleTrack) async; func cue(at seconds: Double) -> String?; var isActive: Bool }` — parsing via `SRTWebVTTConverter`/parsers NativeMediaCore existants.

- [ ] Tests parsing/cue-lookup (chevauchements, trous, HTML strip) sur fixtures SRT.
- [ ] Intégration UI + sélection piste (persistance du choix par item via SettingsStore existant si trivial, sinon session-only).
- [ ] Suites vertes + commit `feat(custom-player): external subtitles overlay (SRT sidecar)`.

### Task 5: Skip intro/générique + épisode suivant

**Files:**
- Create: `PlaybackEngine/Sources/PlaybackEngine/CustomPlayer/SkipSegmentModel.swift` (extraction pure de la logique fenêtres du legacy `PlaybackSessionController+SkipSegments.swift`)
- Modify: `CustomPlaybackEngine.swift` (charge `fetchMediaSegments`, publie `activeSkipSuggestion`, `func skipCurrentSegment()`, `var onPlayNext: (() -> Void)?`)
- Modify: `CustomPlayerView.swift` (bouton skip réutilisant `PlaybackSkipButton`), `DetailView.swift` (queue next-episodes → onPlayNext recharge l'engine)
- Test: Create `Tests/PlaybackEngineTests/SkipSegmentModelTests.swift`

- [ ] Tests fenêtres (entrée/sortie de segment, suggestion unique, fin d'épisode → next).
- [ ] Intégration + commit `feat(custom-player): skip intro/credits + next episode`.

### Task 6: Badge qualité + stats pour les nerds

**Files:**
- Modify: `CustomPlaybackEngine.swift` (expose `struct PlaybackProof { codec, videoRange, resolution, sourceMbps, measuredMbps, lane, cacheHitRatio, rebuilds }` mis à jour au tick)
- Modify: `CustomPlayerView.swift` (badge « Dolby Vision/HDR/SDR » + panneau repliable)
- Test: assertions de mapping dans PlaybackDropResilienceTests (proof.videoRange rempli une fois ready)

- [ ] Implémentation + suites vertes + commit `feat(custom-player): quality badge + nerd stats overlay`.

### Task 7: Custom player par défaut

**Files:**
- Modify: `Shared/Sources/Shared/SettingsStore.swift` (défaut ON via clé « a-été-explicitement-désactivé » pour ne pas écraser un choix utilisateur existant)
- Modify: `ReelFinUI/.../ServerSettingsView.swift` (libellé sans « beta »)
- Modify: `Docs/Custom-Player-Rebuild-Blueprint.md`, mémoire session
- Test: `Tests/PlaybackEngineTests/DefaultSettingsStoreTests.swift` (+1 cas : défaut true, opt-out persistant respecté)

- [ ] Test défaut/opt-out → implémentation → suites complètes iOS + build tvOS → commit `feat(custom-player): make the custom engine the default player`.

## Ordre d'exécution et gates

1 → 2 → 3 → 6 → 7 (cœur « ultime ») puis 4 → 5 (parité UX) si budget de session, sinon sessions suivantes.
Gate final avant Task 7 : suite PlaybackEngineTests complète 0 échec + test live custom engine (ttff/0-stall/réservoir) + build tvOS.
