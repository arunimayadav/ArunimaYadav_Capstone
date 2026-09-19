import Foundation

/// One indexed file. Mirrors the `nodes` table in plan.md section 7.
struct Node: Identifiable, Codable {
    var id: Int64
    var path: String
    var filename: String
    var category: String
    var summary: String
    var tags: [String]
    var confidence: Double
    var status: NodeStatus
    var providerUsed: String
    var extractedText: String
    var embedding: [Float]
    var contentHash: String
    var createdAt: Date
    var updatedAt: Date
}

enum NodeStatus: String, Codable {
    case indexed
    case pendingReview = "pending_review"
    case duplicateSkipped = "duplicate_skipped"
}

/// One entry in the append-only `moves` log.
struct MoveRecord: Identifiable, Codable {
    var id: Int64
    var nodeId: Int64
    var srcPath: String
    var dstPath: String
    var timestamp: Date
    var triggeredBy: String // "command" or "review"
    var reversed: Bool
}

/// One edge in the content graph.
struct Edge: Codable {
    var sourceNodeId: Int64
    var targetNodeId: Int64
    var edgeType: EdgeType
    var weight: Double
}

enum EdgeType: String, Codable {
    case sameTag = "same_tag"
    case sameCategory = "same_category"
    case similarContent = "similar_content"
}

/// The structured result of one AI understanding call, before it becomes a Node.
struct FileUnderstanding {
    var category: String
    var summary: String
    var tags: [String]
    var confidence: Double
    var reasoning: String
}

/// Result of interpreting a free-text organization command, e.g.
/// "create a folder for anything related to my bank and put those files in it".
struct ParsedCommand {
    var destinationFolderName: String
    var searchQuery: String
}
