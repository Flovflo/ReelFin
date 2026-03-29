import Foundation
import GRDB
import Shared

public actor GRDBMetadataRepository: MetadataRepositoryProtocol {
    private let dbPool: DatabasePool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(databaseURL: URL? = nil) throws {
        let url = try (databaseURL ?? DatabaseMigratorFactory.defaultDatabaseURL())
        dbPool = try DatabasePool(path: url.path)
        let migrator = DatabaseMigratorFactory.makeMigrator()
        try migrator.migrate(dbPool)
    }

    public func saveLibraryViews(_ views: [LibraryView]) async throws {
        try await write { db in
            try db.execute(sql: "DELETE FROM library_views")
            for view in views {
                try db.execute(
                    sql: "INSERT INTO library_views (id, name, collection_type) VALUES (?, ?, ?)",
                    arguments: [view.id, view.name, view.collectionType]
                )
            }
        }
    }

    public func fetchLibraryViews() async throws -> [LibraryView] {
        try await read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, name, collection_type FROM library_views ORDER BY name")
            return rows.map {
                LibraryView(id: $0["id"], name: $0["name"], collectionType: $0["collection_type"])
            }
        }
    }

    public func saveHomeFeed(_ feed: HomeFeed) async throws {
        try await write { db in
            try upsert(items: feed.featured, db: db)
            for row in feed.rows {
                try upsert(items: row.items, db: db)
            }

            try db.execute(sql: "DELETE FROM featured_items")
            for (index, item) in feed.featured.enumerated() {
                try db.execute(
                    sql: "INSERT INTO featured_items (item_id, position) VALUES (?, ?)",
                    arguments: [item.id, index]
                )
            }

            try db.execute(sql: "DELETE FROM home_row_items")
            try db.execute(sql: "DELETE FROM home_rows")

            for (rowIndex, row) in feed.rows.enumerated() {
                try db.execute(
                    sql: "INSERT INTO home_rows (id, kind, title, position) VALUES (?, ?, ?, ?)",
                    arguments: [row.id, row.kind.rawValue, row.title, rowIndex]
                )

                for (itemIndex, item) in row.items.enumerated() {
                    try db.execute(
                        sql: "INSERT INTO home_row_items (row_id, item_id, position) VALUES (?, ?, ?)",
                        arguments: [row.id, item.id, itemIndex]
                    )
                }
            }
        }
    }

    public func fetchHomeFeed() async throws -> HomeFeed {
        try await read { db in
            let featuredRows = try Row.fetchAll(
                db,
                sql: """
                SELECT \(mediaItemSelectColumns()) FROM featured_items f
                JOIN media_items m ON m.id = f.item_id
                \(mediaItemProgressJoin())
                ORDER BY f.position
                """
            )
            let featured = featuredRows.compactMap(mediaItem(from:))

            let rowRows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    r.id AS row_id,
                    r.kind AS row_kind,
                    r.title AS row_title,
                    r.position AS row_position,
                    \(mediaItemSelectColumns())
                FROM home_rows r
                LEFT JOIN home_row_items h ON h.row_id = r.id
                LEFT JOIN media_items m ON m.id = h.item_id
                \(mediaItemProgressJoin())
                ORDER BY r.position, h.position
                """
            )

            var rowInfoByID: [String: (kind: String, title: String)] = [:]
            var rowItemsByID: [String: [MediaItem]] = [:]
            var rowOrder: [String] = []

            for row in rowRows {
                let rowID: String = row["row_id"]
                if rowInfoByID[rowID] == nil {
                    rowOrder.append(rowID)
                    rowInfoByID[rowID] = (
                        kind: row["row_kind"],
                        title: row["row_title"]
                    )
                    rowItemsByID[rowID] = []
                }

                if let item = mediaItem(from: row) {
                    rowItemsByID[rowID, default: []].append(item)
                }
            }

            let rows: [HomeRow] = rowOrder.map { rowID in
                let info = rowInfoByID[rowID] ?? (kind: HomeSectionKind.latest.rawValue, title: "")
                return HomeRow(
                    id: rowID,
                    kind: HomeSectionKind(rawValue: info.kind) ?? .latest,
                    title: info.title,
                    items: rowItemsByID[rowID] ?? []
                )
            }

            return HomeFeed(featured: featured, rows: rows)
        }
    }

    public func upsertItems(_ items: [MediaItem]) async throws {
        try await write { db in
            try upsert(items: items, db: db)
        }
    }

    public func fetchItem(id: String) async throws -> MediaItem? {
        try await read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                SELECT \(mediaItemSelectColumns())
                FROM media_items m
                \(mediaItemProgressJoin())
                WHERE m.id = ?
                """,
                arguments: [id]
            )
            return row.flatMap(mediaItem(from:))
        }
    }

    public func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        try await read { db in
            var conditions = ["1 = 1"]
            var arguments = StatementArguments()

            if let viewID = query.viewID {
                conditions.append("m.library_id = ?")
                arguments += [viewID]
            }

            if let mediaType = query.mediaType {
                conditions.append("m.media_type = ?")
                arguments += [mediaType.rawValue]
            }

            if let search = query.query, !search.isEmpty {
                conditions.append("m.name LIKE ?")
                arguments += ["%\(search)%"]
            }

            arguments += [query.pageSize, query.page * query.pageSize]

            let sql = """
                SELECT \(mediaItemSelectColumns())
                FROM media_items m
                \(mediaItemProgressJoin())
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY m.updated_at DESC
                LIMIT ? OFFSET ?
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.compactMap(mediaItem(from:))
        }
    }

    public func searchItems(query: String, limit: Int) async throws -> [MediaItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return try await read { db in
            let escapedQuery = query
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT \(mediaItemSelectColumns()) FROM media_items_fts f
                JOIN media_items m ON m.id = f.media_id
                \(mediaItemProgressJoin())
                WHERE media_items_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """,
                arguments: [escapedQuery + "*", limit]
            )

            return rows.compactMap(mediaItem(from:))
        }
    }

    public func savePlaybackProgress(_ progress: PlaybackProgress) async throws {
        try await write { db in
            try db.execute(
                sql: """
                INSERT INTO playback_progress (item_id, position_ticks, total_ticks, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(item_id) DO UPDATE SET
                    position_ticks = excluded.position_ticks,
                    total_ticks = excluded.total_ticks,
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    progress.itemID,
                    progress.positionTicks,
                    progress.totalTicks,
                    progress.updatedAt
                ]
            )
        }
    }

    public func fetchPlaybackProgress(itemID: String) async throws -> PlaybackProgress? {
        try await read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT item_id, position_ticks, total_ticks, updated_at FROM playback_progress WHERE item_id = ?",
                arguments: [itemID]
            )

            guard let row else { return nil }
            let updatedAt: Date = row["updated_at"]
            return PlaybackProgress(
                itemID: row["item_id"],
                positionTicks: row["position_ticks"],
                totalTicks: row["total_ticks"],
                updatedAt: updatedAt
            )
        }
    }

    public func fetchLastSyncDate() async throws -> Date? {
        try await read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT value FROM sync_state WHERE key = 'last_sync'"
            )
            guard let value: String = row?["value"] else {
                return nil
            }
            return ISO8601DateFormatter().date(from: value)
        }
    }

    public func setLastSyncDate(_ date: Date) async throws {
        try await write { db in
            let value = ISO8601DateFormatter().string(from: date)
            try db.execute(
                sql: """
                INSERT INTO sync_state (key, value)
                VALUES ('last_sync', ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: [value]
            )
        }
    }

    private func upsert(items: [MediaItem], db: Database) throws {
        for item in items {
            try db.execute(
                sql: """
                INSERT INTO media_items (
                    id, name, overview, media_type, year, runtime_ticks, genres,
                    community_rating, poster_tag, backdrop_tag, library_id, parent_id,
                    series_name, series_poster_tag, index_number, parent_index_number,
                    has_4k, has_dolby_vision, has_closed_captions, air_days,
                    is_favorite, is_played, playback_position_ticks, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    overview = excluded.overview,
                    media_type = excluded.media_type,
                    year = excluded.year,
                    runtime_ticks = excluded.runtime_ticks,
                    genres = excluded.genres,
                    community_rating = excluded.community_rating,
                    poster_tag = excluded.poster_tag,
                    backdrop_tag = excluded.backdrop_tag,
                    library_id = excluded.library_id,
                    parent_id = excluded.parent_id,
                    series_name = COALESCE(excluded.series_name, media_items.series_name),
                    series_poster_tag = COALESCE(excluded.series_poster_tag, media_items.series_poster_tag),
                    index_number = COALESCE(excluded.index_number, media_items.index_number),
                    parent_index_number = COALESCE(excluded.parent_index_number, media_items.parent_index_number),
                    has_4k = excluded.has_4k,
                    has_dolby_vision = excluded.has_dolby_vision,
                    has_closed_captions = excluded.has_closed_captions,
                    air_days = excluded.air_days,
                    is_favorite = excluded.is_favorite,
                    is_played = excluded.is_played,
                    playback_position_ticks = COALESCE(excluded.playback_position_ticks, media_items.playback_position_ticks),
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    item.id,
                    item.name,
                    item.overview,
                    item.mediaType.rawValue,
                    item.year,
                    item.runtimeTicks,
                    encodeStringArray(item.genres),
                    item.communityRating,
                    item.posterTag,
                    item.backdropTag,
                    item.libraryID,
                    item.parentID,
                    item.seriesName,
                    item.seriesPosterTag,
                    item.indexNumber,
                    item.parentIndexNumber,
                    item.has4K,
                    item.hasDolbyVision,
                    item.hasClosedCaptions,
                    encodeStringArray(item.airDays ?? []),
                    item.isFavorite,
                    item.isPlayed,
                    item.playbackPositionTicks,
                    Date().timeIntervalSince1970
                ]
            )

            try db.execute(sql: "DELETE FROM media_items_fts WHERE media_id = ?", arguments: [item.id])
            try db.execute(
                sql: "INSERT INTO media_items_fts (media_id, title, overview, genres) VALUES (?, ?, ?, ?)",
                arguments: [item.id, item.name, item.overview ?? "", item.genres.joined(separator: " ")]
            )
        }
    }

    private func mediaItem(from row: Row) -> MediaItem? {
        let id: String? = row["id"]
        let name: String? = row["name"]
        let mediaTypeRaw: String? = row["media_type"]

        guard
            let id,
            let name,
            let mediaTypeRaw,
            let mediaType = MediaType(rawValue: mediaTypeRaw)
        else {
            return nil
        }

        let genresValue: String? = row["genres"]
        let airDaysValue: String? = row["air_days"]
        let storedRuntimeTicks: Int64? = row["runtime_ticks"]
        let storedPlaybackPositionTicks: Int64? = row["playback_position_ticks"]
        let localPlaybackPositionTicks: Int64? = row["local_position_ticks"]
        let localTotalTicks: Int64? = row["local_total_ticks"]
        let isPlayed = (row["is_played"] as Bool?) ?? false

        let effectivePlaybackPositionTicks: Int64?
        if isPlayed {
            effectivePlaybackPositionTicks = nil
        } else if let localPlaybackPositionTicks, localPlaybackPositionTicks > 0 {
            effectivePlaybackPositionTicks = localPlaybackPositionTicks
        } else if let storedPlaybackPositionTicks, storedPlaybackPositionTicks > 0 {
            effectivePlaybackPositionTicks = storedPlaybackPositionTicks
        } else {
            effectivePlaybackPositionTicks = nil
        }

        return MediaItem(
            id: id,
            name: name,
            overview: row["overview"],
            mediaType: mediaType,
            year: row["year"],
            runtimeTicks: effectiveRuntimeTicks(
                storedRuntimeTicks: storedRuntimeTicks,
                localTotalTicks: localTotalTicks,
                playbackPositionTicks: effectivePlaybackPositionTicks
            ),
            genres: decodeStringArray(genresValue),
            communityRating: row["community_rating"],
            posterTag: row["poster_tag"],
            backdropTag: row["backdrop_tag"],
            libraryID: row["library_id"],
            parentID: row["parent_id"],
            seriesName: row["series_name"],
            seriesPosterTag: row["series_poster_tag"],
            indexNumber: row["index_number"],
            parentIndexNumber: row["parent_index_number"],
            has4K: (row["has_4k"] as Bool?) ?? false,
            hasDolbyVision: (row["has_dolby_vision"] as Bool?) ?? false,
            hasClosedCaptions: (row["has_closed_captions"] as Bool?) ?? false,
            airDays: decodeOptionalStringArray(airDaysValue),
            isFavorite: (row["is_favorite"] as Bool?) ?? false,
            isPlayed: isPlayed,
            playbackPositionTicks: effectivePlaybackPositionTicks
        )
    }

    private func mediaItemSelectColumns(mediaAlias: String = "m", progressAlias: String = "p") -> String {
        """
        \(mediaAlias).id,
        \(mediaAlias).name,
        \(mediaAlias).overview,
        \(mediaAlias).media_type,
        \(mediaAlias).year,
        \(mediaAlias).runtime_ticks,
        \(mediaAlias).genres,
        \(mediaAlias).community_rating,
        \(mediaAlias).poster_tag,
        \(mediaAlias).backdrop_tag,
        \(mediaAlias).library_id,
        \(mediaAlias).parent_id,
        \(mediaAlias).series_name,
        \(mediaAlias).series_poster_tag,
        \(mediaAlias).index_number,
        \(mediaAlias).parent_index_number,
        \(mediaAlias).has_4k,
        \(mediaAlias).has_dolby_vision,
        \(mediaAlias).has_closed_captions,
        \(mediaAlias).air_days,
        \(mediaAlias).is_favorite,
        \(mediaAlias).is_played,
        \(mediaAlias).playback_position_ticks,
        \(progressAlias).position_ticks AS local_position_ticks,
        \(progressAlias).total_ticks AS local_total_ticks
        """
    }

    private func mediaItemProgressJoin(mediaAlias: String = "m", progressAlias: String = "p") -> String {
        "LEFT JOIN playback_progress \(progressAlias) ON \(progressAlias).item_id = \(mediaAlias).id"
    }

    private func encodeStringArray(_ values: [String]) -> String {
        let data = (try? encoder.encode(values)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeStringArray(_ value: String?) -> [String] {
        guard
            let value,
            let data = value.data(using: .utf8),
            let decoded = try? decoder.decode([String].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func decodeOptionalStringArray(_ value: String?) -> [String]? {
        let decoded = decodeStringArray(value)
        return decoded.isEmpty ? nil : decoded
    }

    private func effectiveRuntimeTicks(
        storedRuntimeTicks: Int64?,
        localTotalTicks: Int64?,
        playbackPositionTicks: Int64?
    ) -> Int64? {
        let candidates = [storedRuntimeTicks, localTotalTicks, playbackPositionTicks]
            .compactMap { $0 }
            .filter { $0 > 0 }
        return candidates.max()
    }

    private func write<T: Sendable>(_ block: (Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let value = try dbPool.write(block)
                continuation.resume(returning: value)
            } catch {
                AppLog.persistence.error("Write failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: AppError.persistence(error.localizedDescription))
            }
        }
    }

    private func read<T: Sendable>(_ block: (Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let value = try dbPool.read(block)
                continuation.resume(returning: value)
            } catch {
                AppLog.persistence.error("Read failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: AppError.persistence(error.localizedDescription))
            }
        }
    }
}
