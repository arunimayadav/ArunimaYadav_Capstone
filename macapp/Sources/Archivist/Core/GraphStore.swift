import Foundation
import SQLite3

/// Tells sqlite3_bind_text/blob to copy the bytes immediately, rather than trust
/// that our pointer stays valid for the life of the statement (passing `nil`, i.e.
/// SQLITE_STATIC, is wrong here: Swift's String-to-C-string bridging only guarantees
/// the pointer for the duration of the single call it's passed to, so SQLite would be
/// left holding a dangling pointer and can read back garbage/empty data later).
private let SQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed graph memory: nodes, tags, node_tags, edges, moves.
/// Kept as one local file per plan.md section 6/7 — no external graph database.
final class GraphStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "archivist.graphstore")

    init(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            fatalError("Unable to open GraphStore at \(path): \(String(cString: sqlite3_errmsg(db)))")
        }
        createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            fatalError("SQL error: \(message)\nSQL: \(sql)")
        }
    }

    private func createSchema() {
        exec("""
        CREATE TABLE IF NOT EXISTS nodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            filename TEXT NOT NULL,
            category TEXT NOT NULL,
            summary TEXT NOT NULL,
            confidence REAL NOT NULL,
            status TEXT NOT NULL,
            provider_used TEXT NOT NULL,
            extracted_text TEXT NOT NULL,
            embedding BLOB,
            content_hash TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS node_tags (
            node_id INTEGER NOT NULL REFERENCES nodes(id),
            tag_id INTEGER NOT NULL REFERENCES tags(id),
            PRIMARY KEY (node_id, tag_id)
        );

        CREATE TABLE IF NOT EXISTS edges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_node_id INTEGER NOT NULL REFERENCES nodes(id),
            target_node_id INTEGER NOT NULL REFERENCES nodes(id),
            edge_type TEXT NOT NULL,
            weight REAL NOT NULL,
            created_at REAL NOT NULL,
            UNIQUE (source_node_id, target_node_id, edge_type)
        );

        CREATE TABLE IF NOT EXISTS moves (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            node_id INTEGER NOT NULL REFERENCES nodes(id),
            src_path TEXT NOT NULL,
            dst_path TEXT NOT NULL,
            ts REAL NOT NULL,
            triggered_by TEXT NOT NULL,
            reversed INTEGER NOT NULL DEFAULT 0
        );
        """)
    }

    // MARK: - Dedup

    func nodeExists(contentHash: String) -> Bool {
        queue.sync { existingNodeIdLocked(contentHash: contentHash) != nil }
    }

    /// Must be called from within `queue.sync` (or from insertNode, which already
    /// holds the queue) — not public, unlike nodeExists.
    private func existingNodeIdLocked(contentHash: String) -> Int64? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "SELECT id FROM nodes WHERE content_hash = ?;", -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, contentHash, -1, SQLiteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    // MARK: - Insert

    @discardableResult
    func insertNode(path: String, filename: String, understanding: FileUnderstanding,
                     providerUsed: String, extractedText: String, embedding: [Float],
                     contentHash: String, status: NodeStatus) -> Int64 {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let now = Date().timeIntervalSince1970
            sqlite3_prepare_v2(db, """
                INSERT INTO nodes (path, filename, category, summary, confidence, status,
                    provider_used, extracted_text, embedding, content_hash, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, path, -1, SQLiteTransient)
            sqlite3_bind_text(stmt, 2, filename, -1, SQLiteTransient)
            sqlite3_bind_text(stmt, 3, understanding.category, -1, SQLiteTransient)
            sqlite3_bind_text(stmt, 4, understanding.summary, -1, SQLiteTransient)
            sqlite3_bind_double(stmt, 5, understanding.confidence)
            sqlite3_bind_text(stmt, 6, status.rawValue, -1, SQLiteTransient)
            sqlite3_bind_text(stmt, 7, providerUsed, -1, SQLiteTransient)
            sqlite3_bind_text(stmt, 8, extractedText, -1, SQLiteTransient)
            let embeddingData = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            _ = embeddingData.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 9, raw.baseAddress, Int32(raw.count), SQLiteTransient)
            }
            sqlite3_bind_text(stmt, 10, contentHash, -1, SQLiteTransient)
            sqlite3_bind_double(stmt, 11, now)
            sqlite3_bind_double(stmt, 12, now)

            let stepResult = sqlite3_step(stmt)
            guard stepResult == SQLITE_DONE else {
                // Most likely cause: a UNIQUE(content_hash) collision from two
                // overlapping pipeline runs racing on the same file (e.g. a file
                // re-saved while the first run's AI call — which can take minutes —
                // was still in flight, so both passed the dedup check before either
                // had inserted). Look up whichever row actually won the race instead
                // of blindly trusting last_insert_rowid, which would silently point
                // at some unrelated previous insert (or a deleted row) and make the
                // caller's immediate re-read fail with no explanation.
                let message = String(cString: sqlite3_errmsg(db))
                print("[Archivist][GraphStore] insertNode: INSERT failed (\(message)) for \(filename) — " +
                      "looking up the existing row for this content_hash instead")
                return existingNodeIdLocked(contentHash: contentHash) ?? -1
            }
            let nodeId = sqlite3_last_insert_rowid(db)

            for tagName in understanding.tags {
                let tagId = upsertTagLocked(tagName)
                attachTagLocked(nodeId: nodeId, tagId: tagId)
            }
            return nodeId
        }
    }

    private func upsertTagLocked(_ name: String) -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "SELECT id FROM tags WHERE name = ?;", -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, name, -1, SQLiteTransient)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        sqlite3_finalize(stmt)
        stmt = nil
        sqlite3_prepare_v2(db, "INSERT INTO tags (name, created_at) VALUES (?, ?);", -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, name, -1, SQLiteTransient)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
        return sqlite3_last_insert_rowid(db)
    }

    private func attachTagLocked(nodeId: Int64, tagId: Int64) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO node_tags (node_id, tag_id) VALUES (?, ?);", -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, nodeId)
        sqlite3_bind_int64(stmt, 2, tagId)
        sqlite3_step(stmt)
    }

    // MARK: - Read

    func allNodes() -> [Node] {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            sqlite3_prepare_v2(db, "SELECT id FROM nodes ORDER BY created_at DESC;", -1, &stmt, nil)
            var ids: [Int64] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.append(sqlite3_column_int64(stmt, 0))
            }
            return ids.compactMap { nodeLocked(id: $0) }
        }
    }

    func node(id: Int64) -> Node? {
        queue.sync { nodeLocked(id: id) }
    }

    private func nodeLocked(id: Int64) -> Node? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, """
            SELECT path, filename, category, summary, confidence, status, provider_used,
                   extracted_text, embedding, content_hash, created_at, updated_at
            FROM nodes WHERE id = ?;
        """, -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let path = String(cString: sqlite3_column_text(stmt, 0))
        let filename = String(cString: sqlite3_column_text(stmt, 1))
        let category = String(cString: sqlite3_column_text(stmt, 2))
        let summary = String(cString: sqlite3_column_text(stmt, 3))
        let confidence = sqlite3_column_double(stmt, 4)
        let status = NodeStatus(rawValue: String(cString: sqlite3_column_text(stmt, 5))) ?? .indexed
        let provider = String(cString: sqlite3_column_text(stmt, 6))
        let extractedText = String(cString: sqlite3_column_text(stmt, 7))
        let blobLen = sqlite3_column_bytes(stmt, 8)
        var embedding: [Float] = []
        if let blobPtr = sqlite3_column_blob(stmt, 8), blobLen > 0 {
            let count = Int(blobLen) / MemoryLayout<Float>.size
            let buffer = blobPtr.withMemoryRebound(to: Float.self, capacity: count) { $0 }
            embedding = Array(UnsafeBufferPointer(start: buffer, count: count))
        }
        let contentHash = String(cString: sqlite3_column_text(stmt, 9))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11))

        return Node(id: id, path: path, filename: filename, category: category, summary: summary,
                    tags: tagsLocked(nodeId: id), confidence: confidence, status: status,
                    providerUsed: provider, extractedText: extractedText, embedding: embedding,
                    contentHash: contentHash, createdAt: createdAt, updatedAt: updatedAt)
    }

    private func tagsLocked(nodeId: Int64) -> [String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        sqlite3_prepare_v2(db, """
            SELECT t.name FROM tags t
            JOIN node_tags nt ON nt.tag_id = t.id
            WHERE nt.node_id = ?;
        """, -1, &stmt, nil)
        sqlite3_bind_int64(stmt, 1, nodeId)
        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            names.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return names
    }

    func pendingReview() -> [Node] {
        allNodes().filter { $0.status == .pendingReview }
    }

    /// MVP keyword search over filename, content (summary + extracted text), tags,
    /// and category — anything typed about what a file is *called*, what it's
    /// *about*, or how it's *tagged/categorized* should surface it. Embedding-based
    /// ranking (cosine similarity against a query embedding) is the natural next step
    /// once an embedding provider is reliably configured (see plan.md section 9) —
    /// this keyword fallback keeps search usable without one.
    ///
    /// Ranked, not just filtered: a node scores higher per query term the more
    /// "important" the field it matched in is (filename/tags/category > body content),
    /// and higher still if every term matched somewhere. A node needs only one term
    /// to match to appear at all, so a multi-word query doesn't silently return nothing
    /// just because one word wasn't in the file.
    func search(query: String, limit: Int = 20) -> [Node] {
        let needle = query.lowercased()
        let terms = needle.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !terms.isEmpty else { return [] }

        let scored: [(node: Node, score: Int)] = allNodes().compactMap { node in
            let filename = node.filename.lowercased()
            let category = node.category.lowercased()
            let tags = node.tags.map { $0.lowercased() }
            let content = (node.summary + " " + node.extractedText).lowercased()

            var score = 0
            var matchedTerms = 0
            for term in terms {
                var termMatched = false
                if filename.contains(term) { score += 5; termMatched = true }
                if tags.contains(where: { $0.contains(term) }) { score += 4; termMatched = true }
                if category.contains(term) { score += 3; termMatched = true }
                if content.contains(term) { score += 1; termMatched = true }
                if termMatched { matchedTerms += 1 }
            }
            guard matchedTerms > 0 else { return nil }
            if matchedTerms == terms.count { score += 10 } // every word in the query matched somewhere
            return (node, score)
        }

        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.node.createdAt > $1.node.createdAt }
            .prefix(limit)
            .map { $0.node }
    }

    // MARK: - Edges

    func upsertEdge(sourceId: Int64, targetId: Int64, type: EdgeType, weight: Double) {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            sqlite3_prepare_v2(db, """
                INSERT INTO edges (source_node_id, target_node_id, edge_type, weight, created_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(source_node_id, target_node_id, edge_type)
                DO UPDATE SET weight = excluded.weight;
            """, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, sourceId)
            sqlite3_bind_int64(stmt, 2, targetId)
            sqlite3_bind_text(stmt, 3, type.rawValue, -1, SQLiteTransient)
            sqlite3_bind_double(stmt, 4, weight)
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    /// Nodes connected to `nodeId` by any edge, heaviest first.
    func connectedNodes(to nodeId: Int64, limit: Int = 10) -> [Node] {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            sqlite3_prepare_v2(db, """
                SELECT CASE WHEN source_node_id = ?1 THEN target_node_id ELSE source_node_id END AS other,
                       MAX(weight) as w
                FROM edges
                WHERE source_node_id = ?1 OR target_node_id = ?1
                GROUP BY other
                ORDER BY w DESC
                LIMIT ?2;
            """, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, nodeId)
            sqlite3_bind_int64(stmt, 2, Int64(limit))
            var ids: [Int64] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.append(sqlite3_column_int64(stmt, 0))
            }
            return ids.compactMap { nodeLocked(id: $0) }
        }
    }

    // MARK: - Moves

    @discardableResult
    func recordMove(nodeId: Int64, srcPath: String, dstPath: String, triggeredBy: String) -> Int64 {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            sqlite3_prepare_v2(db, """
                INSERT INTO moves (node_id, src_path, dst_path, ts, triggered_by, reversed)
                VALUES (?, ?, ?, ?, ?, 0);
            """, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, nodeId)
            sqlite3_bind_text(stmt, 2, srcPath, -1, SQLiteTransient)
            sqlite3_bind_text(stmt, 3, dstPath, -1, SQLiteTransient)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 5, triggeredBy, -1, SQLiteTransient)
            sqlite3_step(stmt)

            // filename tracks dstPath's basename too, not just path — otherwise a
            // rename (or a folder move that hit a collision suffix) leaves the node's
            // `filename` field stale relative to what's actually on disk.
            var update: OpaquePointer?
            defer { sqlite3_finalize(update) }
            sqlite3_prepare_v2(db, "UPDATE nodes SET path = ?, filename = ?, updated_at = ? WHERE id = ?;", -1, &update, nil)
            sqlite3_bind_text(update, 1, dstPath, -1, SQLiteTransient)
            sqlite3_bind_text(update, 2, URL(fileURLWithPath: dstPath).lastPathComponent, -1, SQLiteTransient)
            sqlite3_bind_double(update, 3, Date().timeIntervalSince1970)
            sqlite3_bind_int64(update, 4, nodeId)
            sqlite3_step(update)

            return sqlite3_last_insert_rowid(db)
        }
    }
}
