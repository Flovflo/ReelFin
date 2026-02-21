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
                SELECT m.* FROM featured_items f
                JOIN media_items m ON m.id = f.item_id
                ORDER BY f.position
                """
            )
            let featured = featuredRows.compactMap(mediaItem(from:))

            let rowRows = try Row.fetchAll(db, sql: "SELECT id, kind, title FROM home_rows ORDER BY position")
            let rows: [HomeRow] = try rowRows.map { row in
                let id: String = row["id"]
                let kindRaw: String = row["kind"]
                let title: String = row["title"]
                let itemRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT m.* FROM home_row_items h
                    JOIN media_items m ON m.id = h.item_id
                    WHERE h.row_id = ?
                    ORDER BY h.position
                    """,
                    arguments: [id]
                )
                let items = itemRows.compactMap(mediaItem(from:))
                return HomeRow(id: id, kind: HomeSectionKind(rawValue: kindRaw) ?? .latest, title: title, items: items)
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
            let row = try Row.fetchOne(db, sql: "SELECT * FROM media_items WHERE id = ?", arguments: [id])
            return row.flatMap(mediaItem(from:))
        }
    }

    public func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        try await read { db in
            var conditions = ["1 = 1"]
            var arguments = StatementArguments()

            if let viewID = query.viewID {
                conditions.append("library_id = ?")
                arguments += [viewID]
            }

            if let mediaType = query.mediaType {
                conditions.append("media_type = ?")
                arguments += [mediaType.rawValue]
            }

            if let search = query.query, !search.isEmpty {
                conditions.append("name LIKE ?")
                arguments += ["%\(search)%"]
            }

            arguments += [query.pageSize, query.page * query.pageSize]

            let sql = """
                SELECT * FROM media_items
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY updated_at DESC
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
                SELECT m.* FROM media_items_fts f
                JOIN media_items m ON m.id = f.media_id
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
                    community_rating, poster_tag, backdrop_tag, library_id, parent_id, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    updated_at = excluded.updated_at
                """,
                arguments: [
                    item.id,
                    item.name,
                    item.overview,
                    item.mediaType.rawValue,
                    item.year,
                    item.runtimeTicks,
                    encodeGenres(item.genres),
                    item.communityRating,
                    item.posterTag,
                    item.backdropTag,
                    item.libraryID,
                    item.parentID,
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
        guard let mediaType = MediaType(rawValue: row["media_type"]) else {
            return nil
        }

        return MediaItem(
            id: row["id"],
            name: row["name"],
            overview: row["overview"],
            mediaType: mediaType,
            year: row["year"],
            runtimeTicks: row["runtime_ticks"],
            genres: decodeGenres(row["genres"]),
            communityRating: row["community_rating"],
            posterTag: row["poster_tag"],
            backdropTag: row["backdrop_tag"],
            libraryID: row["library_id"],
            parentID: row["parent_id"]
        )
    }

    private func encodeGenres(_ genres: [String]) -> String {
        let data = (try? encoder.encode(genres)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeGenres(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8), let decoded = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    private func write<T>(_ block: (Database) throws -> T) async throws -> T {
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

    private func read<T>(_ block: (Database) throws -> T) async throws -> T {
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
