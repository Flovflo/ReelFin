# Architecture Playback Actuelle (ReelFin)

## Objectif
Ce document décrit l'architecture playback actuellement en place dans ReelFin, les choix techniques faits, et les contraintes connues en production (iOS/tvOS).

## Vue d'ensemble
La stack playback est native Apple (AVPlayer/AVFoundation) avec un moteur de décision qui choisit une route parmi:

1. `DirectPlay`
2. `Remux` (direct stream)
3. `Transcode` serveur Jellyfin
4. `NativeBridge` (pipeline local MKV -> fMP4/HLS, voie avancée)

La logique est orchestrée par:

- `PlaybackDecisionEngine` (sélection de la route)
- `PlaybackCoordinator` (résolution des URLs + normalisation des paramètres)
- `PlaybackSessionController` (cycle de vie AVPlayer, watchdogs, recovery)
- `HLSVariantSelector` (sélection/pin de variante HLS)

Fichiers clés:

- `PlaybackEngine/Sources/PlaybackEngine/PlaybackDecisionEngine.swift`
- `PlaybackEngine/Sources/PlaybackEngine/PlaybackCoordinator.swift`
- `PlaybackEngine/Sources/PlaybackEngine/PlaybackSessionController.swift`
- `PlaybackEngine/Sources/PlaybackEngine/HLSVariantSelector.swift`

## Flux de décision

### 1) Évaluation des sources Jellyfin
À partir des `MediaSource`, le moteur évalue:

- container (mkv/mp4/...)
- codecs vidéo/audio (hevc/h264/eac3/aac/...)
- capacités direct play/direct stream
- contraintes policy (auto/originalFirst/originalLockHDRDV)

### 2) Choix de route
Ordre nominal: direct play -> remux -> transcode. En cas de source complexe (souvent MKV + HEVC/HDR), le moteur peut forcer des profils transcode plus compatibles.

### 3) Normalisation transcode
`PlaybackCoordinator` normalise les query params de l'URL HLS:

- `VideoCodec`
- `AllowVideoStreamCopy`
- `Container` / `SegmentContainer`
- `AudioCodec` / `AllowAudioStreamCopy`
- `BreakOnNonKeyFrames`
- `SegmentLength` / `MinSegments`

## Profils transcode utilisés

### `serverDefault`
- Comportement serveur par défaut.
- Peut garder le stream-copy vidéo selon contexte.

### `appleOptimizedHEVC`
- Forçage HEVC transcode côté serveur (`AllowVideoStreamCopy=false`).
- Conteneur fMP4.
- Vise un chemin Apple plus stable que stream-copy MKV/HEVC brut.

### `conservativeCompatibility`
- Profil intermédiaire compatibilité.
- Essaie de limiter les paramètres risqués.

### `forceH264Transcode`
- Fallback de robustesse maximale.
- `VideoCodec=h264`, `RequireAvc=true`, segment TS.
- Priorise la lecture stable, pas la fidélité HDR/DV.

## Récupération (recovery) et stabilité
`PlaybackSessionController` gère:

- watchdog démarrage (no first frame)
- watchdog décodage vidéo
- relances sur profils alternatifs
- anti-boucle de retries

Ajustements récents intégrés:

- watchdog moins agressif en `forceH264Transcode`
- pas de fallback prématuré si `AVPlayerItem` est déjà `readyToPlay`
- `BreakOnNonKeyFrames=False` sur `forceH264Transcode` pour réduire certaines latences de démarrage

## Contraintes techniques importantes

### HDR / Dolby Vision
- Si le profil final est `forceH264Transcode`, le flux est SDR (H264), donc perte HDR/DV.
- Pour conserver HDR, il faut rester sur chemin HEVC compatible (`appleOptimizedHEVC` ou direct/remux HDR viable).

### Formats/sous-titres
- MKV + HEVC + audio HD + sous-titres bitmap = cas coûteux/fragiles.
- Sous-titres burn-in augmentent fortement le coût transcode et le TTFF.

### Démarrage (TTFF)
- Les flux lourds (4K, DV, haut bitrate) peuvent provoquer un `readyToPlay` tardif.
- La stabilité est priorisée par paliers de fallback.

### Logs système iOS/tvOS
Des logs comme `PlayerRemoteXPC ... -12860` ou `FigApplicationStateMonitor ... -19431` apparaissent souvent en bruit système. Ils ne signifient pas automatiquement un bug applicatif fatal.

## Contraintes produit / architecture

- Chemin natif Apple prioritaire (AVPlayer).
- Pas de dépendance VLC/libVLC/FFmpeg comme moteur principal.
- Routage vers transcode serveur obligatoire dès que la source n'est pas nativement fiable.

## Contraintes Git / maintenance

- L'architecture playback a été modularisée dans `PlaybackEngine`.
- Les tests playback sont sous `Tests/PlaybackEngineTests`.
- Pour éviter les régressions: toute modif playback doit inclure au minimum des tests unitaires de décision/URL/variants.

Commandes utiles:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests \
  -only-testing:PlaybackEngineTests/PlaybackPolicyTests \
  -only-testing:PlaybackEngineTests/HLSVariantSelectorTests
```

## État actuel résumé

- Le player est opérationnel sur la voie native AVPlayer.
- Les contenus difficiles peuvent tomber sur `forceH264Transcode` pour garantir lecture/stabilité.
- Dans ce cas, la contrepartie est une image SDR (pas HDR/DV) et parfois un TTFF plus élevé selon la charge transcode serveur.
