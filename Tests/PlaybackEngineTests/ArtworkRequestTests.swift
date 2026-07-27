import Shared
import XCTest

final class ArtworkRequestTests: XCTestCase {
    func testEveryArtworkRoleUsesItsCanonicalProfile() {
        let item = MediaItem(id: "movie-1", name: "Movie", backdropTag: "backdrop")

        let cases: [(ArtworkRequestRole, ArtworkRequestProfile)] = [
            (.posterGrid, .posterGrid),
            (.posterRow, .posterRow),
            (.landscapeRail, .landscapeRail),
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
        let item = MediaItem(id: "movie-1", name: "Movie")

        XCTAssertEqual(ArtworkRequest.make(for: item, role: .landscapeRail).type, .primary)
        XCTAssertEqual(ArtworkRequest.make(for: item, role: .heroLow).type, .primary)
        XCTAssertEqual(ArtworkRequest.make(for: item, role: .heroHigh).type, .primary)
    }

    func testEpisodeArtworkUsesSeriesIdentity() {
        let episode = MediaItem(
            id: "episode-1",
            name: "Episode",
            mediaType: .episode,
            parentID: "series-1"
        )

        for role in ArtworkRequestRole.allCases where role != .logo {
            XCTAssertEqual(ArtworkRequest.make(for: episode, role: role).itemID, "series-1")
        }
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

    func testKnownMissingArtworkDoesNotSchedulePointlessNetworkLoads() {
        let missingMovie = MediaItem(id: "missing", name: "Missing")
        XCTAssertTrue(ArtworkRequest.make(for: missingMovie, role: .posterRow).isKnownMissing)
        XCTAssertTrue(ArtworkRequest.make(for: missingMovie, role: .heroLow).isKnownMissing)

        let primaryOnlyMovie = MediaItem(
            id: "primary",
            name: "Primary",
            posterTag: "primary-tag"
        )
        XCTAssertFalse(ArtworkRequest.make(for: primaryOnlyMovie, role: .posterRow).isKnownMissing)
        XCTAssertFalse(ArtworkRequest.make(for: primaryOnlyMovie, role: .heroLow).isKnownMissing)

        let episodeWithSeries = MediaItem(
            id: "episode",
            name: "Episode",
            mediaType: .episode,
            parentID: "series"
        )
        XCTAssertFalse(ArtworkRequest.make(for: episodeWithSeries, role: .landscapeRail).isKnownMissing)
        XCTAssertFalse(ArtworkRequest.make(for: missingMovie, role: .logo).isKnownMissing)
    }
}
