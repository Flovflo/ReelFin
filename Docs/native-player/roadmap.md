# Roadmap

## Phase 0 - Audit and safety

Done: current AVPlayer route remains default; new flag defaults off.

## Phase 1 - Original file request path

Done: original static stream resolver and range byte source exist.

## Phase 2 - Capability reporting

Started: planner and diagnostics report backend gaps.

## Phase 3 - AVFoundation direct original playback

Started as an MP4 demux helper, not as the architecture boundary.

## Phase 4 - Track enumeration and switching

Started: Matroska and MP4 track enumeration feed session audio/subtitle state.

## Phase 5 - Subtitle overlay system

Started: SRT/WebVTT/ASS parsers and diagnostics exist; overlay timing still needs wiring.

## Phase 6 - VideoToolbox custom decode prototype

Started: H.264 format description path exists; sample decode/render is next.

## Phase 7 - Audio pipeline prototype

Started: decoder/renderer/clock protocols exist; PCM rendering remains incomplete.

## Phase 8 - HDR/Dolby Vision preservation

Started: metadata model and Matroska HDR mapping exist.

## Phase 9 - MKV/custom demux research

Started: real EBML/Matroska parser and basic SimpleBlock extraction exist.

## Phase 10 - Performance hardening

Started: range and pipeline diagnostics exist; no profiling pass yet.

## Phase 11 - QA matrix and regression suite

Started: focused unit tests and honest manual matrix exist.
