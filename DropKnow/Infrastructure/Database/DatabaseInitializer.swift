import Foundation
import SQLite3

/// Bootstraps DropKnow's local SQLite database and applies v1 migration when needed.
public enum DatabaseInitializer {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public struct Configuration: Sendable {
        public let databaseURL: URL
        public let schemaSQLURL: URL
        public let migrationV1SQLURL: URL
        public let busyTimeoutMilliseconds: Int32

        public init(
            databaseURL: URL,
            schemaSQLURL: URL,
            migrationV1SQLURL: URL,
            busyTimeoutMilliseconds: Int32 = 5_000
        ) {
            self.databaseURL = databaseURL
            self.schemaSQLURL = schemaSQLURL
            self.migrationV1SQLURL = migrationV1SQLURL
            self.busyTimeoutMilliseconds = busyTimeoutMilliseconds
        }

        /// Recommended default for a menu bar app:
        /// - database lives in Application Support
        /// - SQL resources live in bundled Infrastructure/Database
        public static func `default`(databaseDirectory: URL, sqlDirectory: URL) -> Configuration {
            let databaseURL = databaseDirectory.appendingPathComponent("dropknow.sqlite3")
            let schemaURL = sqlDirectory.appendingPathComponent("schema.sql")
            let migrationURL = sqlDirectory.appendingPathComponent("migration_v1.sql")
            return Configuration(
                databaseURL: databaseURL,
                schemaSQLURL: schemaURL,
                migrationV1SQLURL: migrationURL
            )
        }

        public static func defaultApplicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupport.appendingPathComponent("DropKnow", isDirectory: true)
        }

        public static func defaultSQLDirectory(bundle: Bundle = .main, fileManager: FileManager = .default) -> URL {
            if let bundledPath = bundle.resourceURL?
                .appendingPathComponent("Infrastructure/Database", isDirectory: true),
               fileManager.fileExists(atPath: bundledPath.appendingPathComponent("schema.sql").path) {
                return bundledPath
            }

            // Local fallback for SwiftPM tests and developer runs.
            return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        }

        public static func appDefault(
            fileManager: FileManager = .default,
            bundle: Bundle = .main
        ) throws -> Configuration {
            try .default(
                databaseDirectory: defaultApplicationSupportDirectory(fileManager: fileManager),
                sqlDirectory: defaultSQLDirectory(bundle: bundle, fileManager: fileManager)
            )
        }
    }

    public enum InitializationError: LocalizedError {
        case openDatabase(message: String)
        case readSQLFile(path: String, underlying: Error)
        case executeSQL(message: String, sqlPreview: String)

        public var errorDescription: String? {
            switch self {
            case .openDatabase(let message):
                return "Failed to open SQLite database: \(message)"
            case .readSQLFile(let path, let underlying):
                return "Failed to read SQL file at \(path): \(underlying.localizedDescription)"
            case .executeSQL(let message, let sqlPreview):
                return "Failed to execute SQL (\(sqlPreview)): \(message)"
            }
        }
    }

    private static let v1MigrationVersion = "v1_initial"

    /// Entry point used by app startup.
    public static func initialize(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(
            at: configuration.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(configuration.databaseURL.path, &db, openFlags, nil)

        guard openResult == SQLITE_OK, let db else {
            let message = String(cString: sqlite3_errmsg(db))
            if db != nil {
                sqlite3_close(db)
            }
            throw InitializationError.openDatabase(message: message)
        }

        defer {
            sqlite3_close(db)
        }

        try execute("PRAGMA foreign_keys = ON;", on: db)
        try execute("PRAGMA journal_mode = WAL;", on: db)
        try execute("PRAGMA busy_timeout = \(configuration.busyTimeoutMilliseconds);", on: db)

        try execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version TEXT PRIMARY KEY,
                description TEXT NOT NULL,
                applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """,
            on: db
        )

        if try migrationExists(version: v1MigrationVersion, on: db) {
            return
        }

        do {
            let migrationSQL = try readSQL(at: configuration.migrationV1SQLURL)
            try execute(migrationSQL, on: db)
        } catch InitializationError.readSQLFile {
            // Fallback: apply schema snapshot and record migration version.
            let schemaSQL = try readSQL(at: configuration.schemaSQLURL)
            try execute("BEGIN IMMEDIATE;", on: db)
            do {
                try execute(schemaSQL, on: db)
                try execute(
                    """
                    INSERT OR IGNORE INTO schema_migrations (version, description)
                    VALUES ('v1_initial', 'Initialized from schema.sql fallback path');
                    """,
                    on: db
                )
                try execute("COMMIT;", on: db)
            } catch {
                _ = try? execute("ROLLBACK;", on: db)
                throw error
            }
        }
    }

    @discardableResult
    public static func initializeDefault(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) throws -> Configuration {
        let configuration = try Configuration.appDefault(fileManager: fileManager, bundle: bundle)
        try initialize(configuration)
        return configuration
    }

    private static func migrationExists(version: String, on db: OpaquePointer) throws -> Bool {
        let sql = "SELECT 1 FROM schema_migrations WHERE version = ? LIMIT 1;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw InitializationError.executeSQL(
                message: String(cString: sqlite3_errmsg(db)),
                sqlPreview: "prepare migration exists query"
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        let versionCString = (version as NSString).utf8String
        sqlite3_bind_text(statement, 1, versionCString, -1, sqliteTransient)
        let stepResult = sqlite3_step(statement)
        return stepResult == SQLITE_ROW
    }

    private static func readSQL(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw InitializationError.readSQLFile(path: url.path, underlying: error)
        }
    }

    private static func execute(_ sql: String, on db: OpaquePointer) throws {
        var errorMessagePointer: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessagePointer)

        guard result == SQLITE_OK else {
            let message: String
            if let errorMessagePointer {
                message = String(cString: errorMessagePointer)
                sqlite3_free(errorMessagePointer)
            } else {
                message = String(cString: sqlite3_errmsg(db))
            }

            let preview = sql
                .replacingOccurrences(of: "\n", with: " ")
                .split(separator: " ")
                .prefix(16)
                .joined(separator: " ")

            throw InitializationError.executeSQL(message: message, sqlPreview: preview)
        }
    }
}
