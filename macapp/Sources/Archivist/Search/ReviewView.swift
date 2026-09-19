import SwiftUI
import AppKit

/// Low-confidence files land here instead of being silently guessed at —
/// plan.md section 5 step 8 / section 8.
struct ReviewView: View {
    let store: GraphStore
    @State private var items: [Node] = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Needs review").font(.headline)
            if items.isEmpty {
                Text("Nothing waiting on review.").foregroundStyle(.secondary)
            }
            List(items) { node in
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.filename).bold()
                    Text(node.summary).font(.caption)
                    Text("Category: \(node.category) · confidence \(String(format: "%.2f", node.confidence))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .onAppear { items = store.pendingReview() }
    }
}
