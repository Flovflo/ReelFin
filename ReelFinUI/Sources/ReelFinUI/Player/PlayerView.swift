import PlaybackEngine
import Shared
import SwiftUI

struct PlayerView: View {
    var session: PlaybackSessionController
    let item: MediaItem
    let onDismiss: () -> Void

    @State private var spinnerRotation: Double = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            // Native iOS/tvOS player controls (scrubber, audio/subtitle menu, PiP, AirPlay).
            NativePlayerViewController(player: session.player)
                .ignoresSafeArea()

            VStack {
                HStack {
                    if debugOverlayEnabled {
                        playbackProofOverlay
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 54)
            .padding(.horizontal, 12)
        }
        .safeAreaInset(edge: .top) {
            topBarControls
                .padding(.horizontal, 12)
                .padding(.top, 6)
        }
        .safeAreaInset(edge: .bottom) {
            let proof = session.playbackProof
            if proof.decodedResolution != "unknown" {
                mediaInfoBar(proof: proof)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.playbackProof.decodedResolution)
        .onDisappear {
            session.pause()
            OrientationManager.shared.lock = .portrait
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
        .onAppear {
            OrientationManager.shared.lock = .allButUpsideDown
            spinnerRotation = 0
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                spinnerRotation = 360
            }
        }
    }

    private var topBarControls: some View {
        HStack(spacing: 10) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playbackProofOverlay: some View {
        let proof = session.playbackProof
        return VStack(alignment: .leading, spacing: 3) {
            Text("Playback Proof")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            if let plan = session.currentPlaybackPlan {
                Text("Lane: \(plan.lane.rawValue)")
                Text("Plan: \(plan.reasonChain.summary)")
            }
            Text("Method: \(proof.playbackMethod)")
            if let profile = proof.transcodeProfile {
                Text("Profile: \(profile)")
            }
            Text("Strict Mode: \(proof.strictQualityModeEnabled ? "on" : "off")")
            Text("Native Path: \(proof.nativePlayerPathActive ? "yes" : "no")")
            Text("Device HDR/DV: \(proof.deviceHDRCapable ? "HDR" : "SDR")/\(proof.deviceDolbyVisionCapable ? "DV" : "no-DV")")
            Text("Decoded: \(proof.decodedResolution)")
            Text("Codec: \(proof.codecFourCC) \(proof.bitDepth.map { "\($0)-bit" } ?? "")")
            Text("HDR Decode: \(proof.hdrTransfer)")
            Text("DV Decode: \(proof.dolbyVisionActive ? "on" : "off")")
            if let dvP = proof.dvProfile, dvP > 0 {
                let sourceState = proof.dolbyVisionActive ? "active" : "metadata-only"
                Text("DV Source: p\(dvP) l\(proof.dvLevel ?? 0) (\(sourceState))")
            }
            if let range = proof.videoRangeType, !range.isEmpty {
                Text("Video Range: \(range)")
            }
            if let sourcePrimaries = proof.sourceColorPrimaries, let sourceTransfer = proof.sourceColorTransfer {
                Text("Source Color: \(sourcePrimaries)/\(sourceTransfer)")
            }
            if let srcBitrate = proof.sourceBitrate, srcBitrate > 0 {
                Text("Source: \(proof.sourceContainer ?? "?") \(proof.sourceVideoCodec ?? "?") @ \(formatBitrate(srcBitrate))")
            }
            if let selectedAudio = proof.sourceAudioTrackSelected {
                Text("Audio Track: \(selectedAudio)")
            }
            if let variantRes = proof.variantResolution {
                Text("Variant: \(variantRes) @ \(formatBitrate(proof.variantBandwidth ?? 0))")
            }
            if let selectedRange = proof.selectedVideoRange {
                Text("Variant Range: \(selectedRange)")
            }
            if let supplemental = proof.selectedSupplementalCodecs, !supplemental.isEmpty {
                Text("Supplemental: \(supplemental)")
            }
            if let transport = proof.selectedTransport {
                Text("Transport: \(transport)")
            }
            Text("Init hvcC/dvcC/dvvC: \(proof.initHasHvcC ? "1" : "0")/\(proof.initHasDvcC ? "1" : "0")/\(proof.initHasDvvC ? "1" : "0")")
            Text("Effective Mode: \(proof.inferredEffectiveVideoMode)")
            if let observed = proof.observedBitrate, observed > 0 {
                Text("Observed: \(formatBitrate(observed))")
            }
            if let codecs = proof.variantCodecs, !codecs.isEmpty {
                Text("Codecs: \(codecs)")
            }
            if let masterURL = proof.selectedMasterPlaylistURL {
                Text("Master: \(masterURL)")
            }
            if let variantURL = proof.selectedVariantURL {
                Text("Variant URL: \(variantURL)")
            }
            Text("Item Status: \(proof.playerItemStatus)")
            if proof.fallbackOccurred {
                Text("Fallback: yes (\(proof.fallbackReason ?? "unknown"))")
            }
            if let domain = proof.failureDomain {
                Text("Error: \(domain)#\(proof.failureCode ?? 0)")
            }
            if let reason = proof.failureReason {
                Text("FailureReason: \(reason)")
            }
            if let suggestion = proof.recoverySuggestion {
                Text("Recovery: \(suggestion)")
            }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(Color.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var debugOverlayEnabled: Bool {
        UserDefaults.standard.bool(forKey: "reelfin.playback.debugOverlay.enabled")
    }

    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else if bps >= 1_000 {
            return "\(bps / 1_000) Kbps"
        }
        return "\(bps) bps"
    }

    @ViewBuilder
    private func mediaInfoBar(proof: PlaybackProofSnapshot) -> some View {
        HStack(spacing: 0) {
            // Video codec + bit depth
            let codec = proof.codecFourCC != "unknown" ? proof.codecFourCC.uppercased() : "—"
            let depth = proof.bitDepth.map { "·\($0)b" } ?? ""
            mediaInfoChip(codec + (depth.isEmpty ? "" : " " + depth), icon: "video.fill")

            // Audio codec
            if let audio = proof.sourceAudioCodec, !audio.isEmpty {
                mediaInfoDivider
                mediaInfoChip(audio.uppercased(), icon: "speaker.wave.2.fill")
            }

            // Resolution
            mediaInfoDivider
            mediaInfoChip(proof.decodedResolution, icon: "rectangle.fill")

            // Source bitrate
            if let bitrate = proof.sourceBitrate, bitrate > 0 {
                mediaInfoDivider
                mediaInfoChip(formatBitrate(bitrate), icon: "waveform")
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
    }

    private func mediaInfoChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.7)
            Text(text)
        }
        .padding(.horizontal, 11)
    }

    private var mediaInfoDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 13)
    }
}
