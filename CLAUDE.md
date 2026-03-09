# Project: ReelFin (iOS 26 Native Video Player)

## Quick Reference
- **Platform**: iOS 26+ / tvOS (si applicable)
- **Language**: Swift 6.0 (Strict Concurrency Obligatoire)
- **UI Framework**: SwiftUI (Composants NATIFS uniquement, aucun bouton custom inutile)
- **Architecture**: MVVM avec `@Observable` (Aucun `ObservableObject`)

## Core Directives (App Store Ready)
1. **Performance Absolue** : Le Time To First Frame (TTFF) doit être quasi-nul. Pas de blocage du Main Thread.
2. **Native iOS 26** : Utilise les APIs natives Apple (`AVFoundation`, `AVAssetResourceLoaderDelegate`). Les boutons et contrôles doivent être les standards iOS (symboles SFSymbols, boutons natifs SwiftUI) pour garantir l'accessibilité et la fluidité.
3. **App Store Review** : Code extrêmement propre, aucune API privée gérant la vidéo. Respect des guidelines Apple sur la gestion mémoire.

## Features Stratégiques
- **Player** : Direct-play MKV vers fMP4 pipeline, support HEVC 10-bit Dolby Vision (Profile 8.1) / HDR10.
- **Audio/Subtitles** : Switch complet (E-AC3, TrueHD Atmos, SRT, PGS).
- **Metadata UI** : Affichage des infos fichiers (taille, bitrate, codec) en mode "glassmorphism" très subtil en bas de l'écran (UX non intrusive).

## MCP & Testing
- Utilise `mcp__xcodebuildmcp__build_sim_name_proj` pour build.
- Ne propose pas de code non testé mentalement. Utilise `ultrathink` pour les décisions d'architecture vidéo complexes (Remuxing).
