import Foundation
import GRDB

enum DatabaseMigratorFactory {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_schema") { db in
            try db.create(table: "library_views") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("collection_type", .text)
            }

            try db.create(table: "media_items") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("overview", .text)
                t.column("media_type", .text).notNull()
                t.column("year", .integer)
                t.column("runtime_ticks", .integer)
                t.column("genres", .text).notNull().defaults(to: "[]")
                t.column("community_rating", .double)
                t.column("poster_tag", .text)
                t.column("backdrop_tag", .text)
                t.column("library_id", .text)
                t.column("parent_id", .text)
                t.column("updated_at", .double).notNull()
            }

            try db.create(index: "idx_media_items_library", on: "media_items", columns: ["library_id"])
            try db.create(index: "idx_media_items_type", on: "media_items", columns: ["media_type"])
            try db.create(index: "idx_media_items_updated", on: "media_items", columns: ["updated_at"])

            try db.execute(sql: """
                CREATE VIRTUAL TABLE media_items_fts USING fts5(
                    media_id UNINDEXED,
                    title,
                    overview,
                    genres
                );
                """)

            try db.create(table: "home_rows") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("position", .integer).notNull()
            }

            try db.create(table: "home_row_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("row_id", .text).notNull().references("home_rows", onDelete: .cascade)
                t.column("item_id", .text).notNull().references("media_items", onDelete: .cascade)
                t.column("position", .integer).notNull()
            }

            try db.create(index: "idx_home_row_items_row", on: "home_row_items", columns: ["row_id", "position"])

            try db.create(table: "featured_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("item_id", .text).notNull().references("media_items", onDelete: .cascade)
                t.column("position", .integer).notNull()
            }

            try db.create(table: "playback_progress") { t in
                t.column("item_id", .text).primaryKey().references("media_items", onDelete: .cascade)
                t.column("position_ticks", .integer).notNull()
                t.column("total_ticks", .integer).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "sync_state") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }
        }

        return migrator
    }

    static func defaultDatabaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("ReelFin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("metadata.sqlite")
    }
}
