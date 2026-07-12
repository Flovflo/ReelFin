import Foundation
import Observation
import Shared

/// An external (sidecar) subtitle track the player can render itself. AVFoundation cannot inject
/// external text tracks into a progressive asset, so the player draws these as an overlay —
/// exactly how Infuse renders its subtitles.
public struct ExternalSubtitleTrack: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let url: URL

    public init(id: String, label: String, url: URL) {
        self.id = id
        self.label = label
        self.url = url
    }
}

/// Downloads, parses, and serves external SRT/VTT cues by playback time. Pure text pipeline —
/// selection is confirmed only after download and parsing succeed. Failures are surfaced through
/// the owning player's existing error path. The engine feeds `updateTime` from a periodic observer;
/// the player view renders `currentCue`.
@MainActor
@Observable
public final class SubtitleOverlayModel {
    public private(set) var availableTracks: [ExternalSubtitleTrack] = []
    public private(set) var pendingTrackID: String?
    public private(set) var activeTrackID: String?
    public private(set) var currentCue: String?
    public private(set) var loadErrorMessage: String?

    struct TimedCue {
        let start: Double
        let end: Double
        let text: String
    }

    private var cues: [TimedCue] = []
    private var loadTask: Task<Void, Never>?
    private let cueLoader: @Sendable (URL) async -> [TimedCue]?
    var onLoadFailure: ((String) -> Void)?
    /// Cache of the last lookup index — cues are sorted and playback is monotonic, so lookup is
    /// O(1) amortized instead of a scan per tick.
    private var lookupIndex = 0

    public init() {
        cueLoader = { url in await Self.loadCues(from: url) }
    }

    init(loadCues: @escaping @Sendable (URL) async -> [TimedCue]?) {
        cueLoader = loadCues
    }

    public func configure(tracks: [ExternalSubtitleTrack]) {
        availableTracks = tracks
        loadErrorMessage = nil
        select(trackID: nil)
    }

    /// Selects a track (nil = off). Downloading + parsing happen off the main thread.
    public func select(trackID: String?) {
        loadTask?.cancel()
        pendingTrackID = nil
        loadErrorMessage = nil
        guard let trackID else {
            activeTrackID = nil
            cues = []
            currentCue = nil
            lookupIndex = 0
            return
        }
        guard let track = availableTracks.first(where: { $0.id == trackID }) else { return }
        pendingTrackID = trackID
        loadTask = Task { [weak self] in
            guard let self else { return }
            guard let parsed = await self.cueLoader(track.url) else {
                guard !Task.isCancelled, self.pendingTrackID == trackID else { return }
                self.pendingTrackID = nil
                let message = "Impossible de charger ou d’analyser les sous-titres sélectionnés."
                self.loadErrorMessage = message
                self.onLoadFailure?(message)
                return
            }
            guard !Task.isCancelled, self.pendingTrackID == trackID else { return }
            self.pendingTrackID = nil
            self.activeTrackID = trackID
            self.cues = parsed
            self.currentCue = nil
            self.lookupIndex = 0
        }
    }

    /// Called by the engine's periodic time observer with the TITLE position.
    public func updateTime(_ seconds: Double) {
        guard !cues.isEmpty else {
            if currentCue != nil { currentCue = nil }
            return
        }
        // Seek backwards → restart the cursor (time landed at or before a cue already consumed);
        // otherwise advance monotonically.
        if lookupIndex >= cues.count || (lookupIndex > 0 && cues[lookupIndex - 1].end >= seconds) {
            lookupIndex = 0
        }
        while lookupIndex < cues.count, cues[lookupIndex].end < seconds {
            lookupIndex += 1
        }
        let cue: String?
        if lookupIndex < cues.count, cues[lookupIndex].start <= seconds, seconds <= cues[lookupIndex].end {
            cue = cues[lookupIndex].text
        } else {
            cue = nil
        }
        if currentCue != cue { currentCue = cue }
    }

#if DEBUG
    /// Test hook: install cues synchronously from raw SRT text (no network).
    public func debugInstall(cuesFrom text: String) {
        cues = Self.parse(text: text) ?? []
        lookupIndex = 0
        currentCue = nil
    }
#endif

    // MARK: - Loading / parsing (static + nonisolated: runs off the MainActor)

    nonisolated private static func loadCues(from url: URL) async -> [TimedCue]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Subtitle sidecars live on the same Jellyfin origin as the media. Reuse the process-lived
        // transport instead of creating an ephemeral session that forgets the tvOS H3→H2 verdict.
        guard let (data, response) = try? await MediaOriginTransport.onDemand.data(for: request),
              (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        return parse(text: text)
    }

    nonisolated static func parse(text: String) -> [TimedCue]? {
        // SRT first (the overwhelmingly common sidecar), VTT accepted via the same converter's
        // timestamp shapes. ASS/PGS are out of scope for the overlay (the MP4 twin or transcode
        // carries those).
        guard let document = try? SRTWebVTTConverter().convert(text.hasPrefix("WEBVTT") ? Self.stripVTTHeader(text) : text) else {
            return nil
        }
        let timed: [TimedCue] = document.cues.compactMap { cue in
            guard let start = seconds(fromVTTTimestamp: cue.start),
                  let end = seconds(fromVTTTimestamp: cue.end), end > start else { return nil }
            return TimedCue(start: start, end: end, text: Self.plainText(from: cue.payload))
        }
        return timed.isEmpty ? nil : timed.sorted { $0.start < $1.start }
    }

    nonisolated private static func stripVTTHeader(_ text: String) -> String {
        // Re-shape a VTT body into the SRT-ish block list the converter accepts: drop the header
        // line and cue settings after timestamps are handled by the converter's sanitizer.
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()
            .joined(separator: "\n")
    }

    /// "HH:MM:SS.mmm" or "MM:SS.mmm" → seconds.
    nonisolated static func seconds(fromVTTTimestamp raw: String) -> Double? {
        let core = raw.split(separator: " ").first.map(String.init) ?? raw
        let parts = core.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let secondsPart = parts.last?.replacingOccurrences(of: ",", with: ".") ?? "0"
        guard let secs = Double(secondsPart) else { return nil }
        let minutes = Double(parts[parts.count - 2]) ?? 0
        let hours = parts.count == 3 ? (Double(parts[0]) ?? 0) : 0
        return hours * 3_600 + minutes * 60 + secs
    }

    /// Strips basic markup ({\an8}, <i>…</i>) — the overlay renders plain text.
    nonisolated static func plainText(from payload: String) -> String {
        var text = payload
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
