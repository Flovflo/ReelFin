import Shared
import XCTest

final class ArtworkRequestTests: XCTestCase {
    func testEveryArtworkRoleUsesItsCanonicalProfile() {
        let item = MediaItem(id: "movie-1", name: "Movie", backdropTag: "backdrop")

        let cases: [(ArtworkRequestRole, ArtworkRequestProfile)] = [
            (.posterGrid, .posterGrid),
            (.posterRow, .posterRow),
            (.landscapeRail, .landscapeRail),
            (.episodeStill, .landscapeRail),
            (.heroLow, .heroBackdropLow),
            (.heroHigh, .heroBackdropHigh),
            (.logo, .logo),
            (.avatar, .avatar)
        ]

        XCTAssertEqual(ArtworkRequestRole.allCases.count, cases.count)
        for (role, expectedProfile) in cases {
            XCTAssertEqual(ArtworkRequest.make(for: item, role: role).profile, expectedProfile)
        }
    }

    func testPosterRolesUsePrimaryArtworkOnDisplayedItem() {
        let item = MediaItem(id: "movie-1", name: "Movie", backdropTag: "backdrop")

        let gridRequest = ArtworkRequest.make(for: item, role: .posterGrid)
        XCTAssertEqual(gridRequest.itemID, "movie-1")
        XCTAssertEqual(gridRequest.type, .primary)
        XCTAssertEqual(gridRequest.profile, .posterGrid)

        let rowRequest = ArtworkRequest.make(for: item, role: .posterRow)
        XCTAssertEqual(rowRequest.itemID, "movie-1")
        XCTAssertEqual(rowRequest.type, .primary)
        XCTAssertEqual(rowRequest.profile, .posterRow)
    }

    func testLandscapeAndHeroRolesPreferBackdropWhenAvailable() {
        let item = MediaItem(id: "movie-1", name: "Movie", backdropTag: "backdrop")

        XCTAssertEqual(ArtworkRequest.make(for: item, role: .landscapeRail).type, .backdrop)
        XCTAssertEqual(ArtworkRequest.make(for: item, role: .heroLow).type, .backdrop)
        XCTAssertEqual(ArtworkRequest.make(for: item, role: .heroHigh).type, .backdrop)
    }

    func testLandscapeAndHeroRolesFallBackToPrimaryWhenBackdropIsUnavailable() {
        let item = MediaItem(id: "movie-1", name: "Movie", posterTag: "poster")

        XCTAssertEqual(ArtworkRequest.make(for: item, role: .landscapeRail).type, .primary)
        XCTAssertEqual(ArtworkRequest.make(for: item, role: .heroLow).type, .primary)
        XCTAssertEqual(ArtworkRequest.make(for: item, role: .heroHigh).type, .primary)
    }

    func testTaglessLandscapeAndHeroRolesPreferRemoteBackdropShape() {
        let item = MediaItem(id: "movie-1", name: "Movie")

        XCTAssertEqual(ArtworkRequest.make(for: item, role: .landscapeRail).type, .backdrop)
        XCTAssertEqual(ArtworkRequest.make(for: item, role: .heroLow).type, .backdrop)
        XCTAssertEqual(ArtworkRequest.make(for: item, role: .heroHigh).type, .backdrop)
    }

    func testEpisodeArtworkUsesSeriesIdentity() {
        let episode = MediaItem(
            id: "episode-1",
            name: "Episode",
            mediaType: .episode,
            parentID: "series-1"
        )

        for role in ArtworkRequestRole.allCases where role != .logo && role != .episodeStill {
            XCTAssertEqual(ArtworkRequest.make(for: episode, role: role).itemID, "series-1")
        }
    }

    func testEpisodeStillUsesTheEpisodePrimaryImage() {
        let episode = MediaItem(
            id: "episode-1",
            name: "Episode",
            mediaType: .episode,
            parentID: "series-1"
        )

        let request = ArtworkRequest.make(for: episode, role: .episodeStill)

        XCTAssertEqual(request.itemID, "episode-1")
        XCTAssertEqual(request.type, .primary)
        XCTAssertEqual(request.profile, .landscapeRail)
        XCTAssertTrue(request.allowsSpeculativePrefetch)
        XCTAssertTrue(request.shouldProbeLocal)
    }

    func testEpisodeLandscapeArtworkUsesParentSeriesBackdropWithoutEpisodeBackdropTag() {
        let episode = MediaItem(
            id: "episode-1",
            name: "Episode",
            mediaType: .episode,
            parentID: "series-1"
        )

        XCTAssertEqual(ArtworkRequest.make(for: episode, role: .landscapeRail).type, .backdrop)
        XCTAssertEqual(ArtworkRequest.make(for: episode, role: .heroLow).type, .backdrop)
        XCTAssertEqual(ArtworkRequest.make(for: episode, role: .heroHigh).type, .backdrop)
    }

    func testEpisodeArtworkFallsBackToEpisodeIdentityWithoutParent() {
        let episode = MediaItem(id: "episode-1", name: "Episode", mediaType: .episode)

        XCTAssertEqual(ArtworkRequest.make(for: episode, role: .landscapeRail).itemID, "episode-1")
    }

    func testLogoUsesDisplayedItemIdentityAndLogoType() {
        let episode = MediaItem(
            id: "episode-1",
            name: "Episode",
            mediaType: .episode,
            parentID: "series-1"
        )

        let request = ArtworkRequest.make(for: episode, role: .logo)
        XCTAssertEqual(request.itemID, "episode-1")
        XCTAssertEqual(request.type, .logo)
        XCTAssertEqual(request.profile, .logo)
    }

    func testMissingImageTagsDisableSpeculativePrefetchOnly() {
        let taglessMovie = MediaItem(id: "tagless", name: "Tagless")
        XCTAssertFalse(
            ArtworkRequest.make(for: taglessMovie, role: .posterRow).allowsSpeculativePrefetch
        )
        XCTAssertFalse(
            ArtworkRequest.make(for: taglessMovie, role: .heroLow).allowsSpeculativePrefetch
        )

        let primaryOnlyMovie = MediaItem(
            id: "primary",
            name: "Primary",
            posterTag: "primary-tag"
        )
        XCTAssertTrue(
            ArtworkRequest.make(for: primaryOnlyMovie, role: .posterRow).allowsSpeculativePrefetch
        )
        XCTAssertTrue(
            ArtworkRequest.make(for: primaryOnlyMovie, role: .heroLow).allowsSpeculativePrefetch
        )

        let episodeWithSeries = MediaItem(
            id: "episode",
            name: "Episode",
            mediaType: .episode,
            parentID: "series"
        )
        XCTAssertTrue(
            ArtworkRequest.make(for: episodeWithSeries, role: .landscapeRail).allowsSpeculativePrefetch
        )
        XCTAssertTrue(
            ArtworkRequest.make(for: taglessMovie, role: .logo).allowsSpeculativePrefetch
        )
    }

    func testTaglessTopLevelItemSkipsKnownMissingLocalArtworkButEpisodeKeepsUnknownProbe() {
        let taglessMovie = MediaItem(id: "tagless", name: "Tagless")
        let episode = MediaItem(
            id: "episode",
            name: "Episode",
            mediaType: .episode,
            parentID: "series"
        )

        XCTAssertFalse(ArtworkRequest.make(for: taglessMovie, role: .heroHigh).shouldProbeLocal)
        XCTAssertTrue(ArtworkRequest.make(for: episode, role: .landscapeRail).shouldProbeLocal)
    }

    func testTaglessAvatarStillProbesAndPrefetchesPersonPrimaryArtwork() {
        let person = MediaItem(id: "person-1", name: "Actor")
        let request = ArtworkRequest.make(for: person, role: .avatar)

        XCTAssertEqual(request.itemID, "person-1")
        XCTAssertEqual(request.type, .primary)
        XCTAssertTrue(request.shouldProbeLocal)
        XCTAssertTrue(request.allowsSpeculativePrefetch)
    }
}
