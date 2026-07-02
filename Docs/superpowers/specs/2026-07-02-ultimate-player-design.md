# Le Player Ultime — Design (2026-07-02)

Objectif utilisateur, verbatim : « le meilleur player possible, la meilleure expérience possible :
début ultra rapide, surtout pas de coupure/lag, et une qualité MAX en HDR Dolby Vision ».

## Décision d'architecture : compléter, pas repartir de zéro

L'utilisateur autorise un restart complet. Rejeté : le cœur actuel (OriginDownloader parallèle →
MediaGatewayStore réécrit → LocalCacheHTTPServer → AVPlayer, gate fast-start dynamique, recovery
ladder) vient d'être prouvé contre le vrai serveur — ttff 3,4 s, 0 stall, réservoir 356 s
(commit `34839cb`). Un rebuild from scratch rejouerait des mois de root-causes (DV black-screen du
resource loader, churn de connexions, jetsam, écran noir du transcode global…) sans gain. Le
blueprint (`Docs/Custom-Player-Rebuild-Blueprint.md`) EST déjà le design from-scratch ; ce chantier
en livre les capacités restantes, dans l'ordre de valeur utilisateur.

Alternatives considérées :
- **From scratch (rejeté)** — détruit du proven, réintroduit les régressions connues.
- **Améliorer le legacy (rejeté)** — 9 300 lignes, 4 couches de fallback enchevêtrées ; le blueprint
  le condamne déjà.
- **Compléter le custom engine (retenu)** — chaque lot est additif, testable offline, gated.

## Les 7 lots (ordre de valeur)

### Lot 1 — Démarrage perçu < 1 s : préchauffage à la fiche détail
Aujourd'hui le pipeline entier (résolution Jellyfin ~1 s + prime + coussin 6 s) démarre au tap.
Pendant que l'utilisateur lit la fiche (3-10 s typiques), tout cela peut être déjà fait.
- `CustomPlayerPrewarmer` (PlaybackEngine) : `prewarm(itemID:)` → résout la source, construit la
  `CacheProxySession` (serveur localhost + primeStart), SANS AVPlayer. Cache mono-entrée (le
  dernier item préchauffé), `consume(itemID:)` la transfère au moteur, `discard()` la libère
  (idempotent, jamais deux sessions sur la même clé).
- `CustomPlaybackEngine.load` adopte la session préchauffée si l'itemID correspond (sinon flux
  actuel inchangé). Le gate fast-start voit alors un réservoir déjà ≥ cible → `playOriginalNow`.
- `DetailView.onAppear` (flag custom ON) déclenche le prewarm ; onDisappear sans lecture → discard.
- Trade-off assumé : quelques Mo téléchargés pour des fiches jamais lues (borné : prime ≈ 12 Mo +
  remplissage du coussin ; le downloader idle au-delà du budget ahead).

### Lot 2 — Never-cut absolu : lane SDR de dernier recours + retour auto au DV
Le seul scénario restant « pas bien » : lien durablement < bitrate → barre de chargement sans fin
(honnête, mais pas « jamais de lag »). Décision produit (confirmée par l'utilisateur les sessions
précédentes) : après une inability PROUVÉE et SOUTENUE, basculer sur le transcode HLS H.264 propre
(tone-mapping serveur, jamais le HDR10 sombre), puis REVENIR au DV automatiquement quand le lien
re-tient. Original-first : jamais au démarrage, jamais sur un dip.
- `PlaybackLanePolicy.steadyAction` existe déjà (`dropToSDRLastResort` après
  `lastResortSustainedSeconds=90` sous bitrate) — le câbler enfin : le moteur suit
  `ConnectionMonitor.sustainedBelowBitrateSeconds` (déjà alimenté chaque seconde) ET exige
  `phase == .buffering` (réservoir vide) pour déclencher.
- Résolution du flux SDR : `JellyfinOriginalSourceResolver.resolveAdaptiveFallback(itemID:)` →
  PlaybackInfo avec `EnableTranscoding=true` + profil H.264/TS (le pattern prouvé du test live
  `transcodingMasterURL`) → `TranscodingUrl` master.m3u8. SCOPÉ à cet appel (leçon mémoire :
  jamais global — écran noir de démarrage).
- Swap : `replaceCurrentItem` à `currentTime` (AVURLAsset HLS normal), la `CacheProxySession` DV
  reste VIVANTE (le downloader continue de remplir). État UI `degradedSDR` (badge « Qualité
  adaptée »).
- Upgrade back : en SDR, le moteur continue de mesurer le fill-rate du réservoir DV (le downloader
  tourne). Quand headroom ≥ 1,3× soutenu 30 s ET réservoir DV ≥ 30 s au timestamp courant → swap
  retour au localhost à `currentTime`. Hystérésis : max 1 downgrade puis 1 upgrade par fenêtre de
  5 min (anti-flap) ; après 2 échecs d'upgrade, rester SDR jusqu'à la fin du titre.
- Policy pure `AdaptiveLanePolicy` (décisions downgrade/upgrade/anti-flap) → 100 % unit-testée.

### Lot 3 — AirPlay et PiP corrects
- AirPlay : `allowsExternalPlayback` réactivé, mais KVO sur `isExternalPlaybackActive` → actif :
  swap l'item vers l'URL ORIGINE (l'Apple TV tire directement du serveur, localhost injoignable) à
  `currentTime` ; désactivé : retour au localhost (cache intact). 
- PiP : `AVPlayerViewController.delegate` → willStart/didStop PiP ; `CustomPlayerView.onDisappear`
  ne stoppe plus le moteur si PiP actif ; restauration propre au retour.

### Lot 4 — Sous-titres externes (SRT/VTT sidecar)
AVKit affiche déjà les pistes EMBARQUÉES du MP4. Les sous-titres externes Jellyfin (SRT/ASS
sidecar), invisibles d'AVFoundation en lecture progressive, sont rendus par NOTRE overlay :
- `SubtitleOverlayModel` : télécharge `/Videos/{id}/{sourceId}/Subtitles/{index}/Stream.srt`,
  parse (SRTWebVTTConverter existant), expose `cue(at time:)` ; le moteur publie le temps via
  periodic time observer (0,25 s).
- `CustomPlayerView` : texte overlay bas centré (style système, fond translucide), pilotée par le
  modèle ; menu de sélection (pistes externes listées depuis la MediaSource déjà résolue).
- Hors scope ici : ASS stylé complet (rendu texte brut), PGS bitmap (impossible sans décodeur — le
  twin MP4/le transcode les brûle si besoin).

### Lot 5 — Skip intro/générique + épisode suivant
- Réutilise `fetchMediaSegments(itemID:)` + la logique de fenêtres du legacy
  (`PlaybackSessionController+SkipSegments`) extraite en `SkipSegmentModel` pur.
- Bouton overlay « Passer l'intro » (compte à rebours), « Épisode suivant » sur le segment final +
  à `didPlayToEnd` → `onPlayNext` (DetailView fournit la queue déjà calculée pour le legacy).

### Lot 6 — Stats & confiance qualité
- Badge live dans le HUD : « Dolby Vision » (videoRangeType réel de l'asset une fois ready),
  résolution, bitrate source.
- Panneau « Stats pour les nerds » (toggle) : débit mesuré, réservoir, lane, hits cache vs
  on-demand, rebuilds.

### Lot 7 — Bascule par défaut + nettoyage
- `useCustomPlayerEngine` par défaut **ON** (le toggle Réglages permet le retour legacy).
- Docs + mémoire à jour. (La suppression physique du legacy = Phase 7 du blueprint, chantier
  séparé.)

## Ce qui est explicitement hors scope (et pourquoi)
- **Trickplay au scrub** : exige un chrome 100 % custom (AVPlayerViewController ne l'expose pas en
  progressif). Gros chantier UI dédié — après la parité.
- **Remux MP4 stream-copy pour MKV-only** (garder DV P8 quand pas de twin) : à valider contre le
  serveur réel (seek/range sur remux à la volée incertain) — exploration séparée.
- **tvOS custom player par défaut** : le proxy reste iOS-first tant que non validé device tvOS.

## Tests
Chaque lot : policy pure → tests unitaires ; intégration moteur → harness ThrottledDropHTTPServer
(offline) ; les invariants live existants restent le gate (ttff, 0 stall, réservoir).
