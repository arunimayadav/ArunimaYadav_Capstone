import Foundation

/// Turns shared tags/category/embedding similarity into graph edges — plan.md
/// section 6. Kept simple (compare against all existing nodes) since the graph is
/// small by design (plan.md section 8).
enum RelationshipBuilder {
    static func relate(node: Node, in store: GraphStore) {
        let others = store.allNodes().filter { $0.id != node.id }
        for other in others {
            let sharedTags = Set(node.tags).intersection(other.tags)
            if !sharedTags.isEmpty {
                store.upsertEdge(sourceId: node.id, targetId: other.id, type: .sameTag, weight: Double(sharedTags.count))
            }
            if node.category == other.category {
                store.upsertEdge(sourceId: node.id, targetId: other.id, type: .sameCategory, weight: 1.0)
            }
            if !node.embedding.isEmpty && !other.embedding.isEmpty {
                let similarity = cosineSimilarity(node.embedding, other.embedding)
                if similarity > 0.75 {
                    store.upsertEdge(sourceId: node.id, targetId: other.id, type: .similarContent, weight: Double(similarity))
                }
            }
        }
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
