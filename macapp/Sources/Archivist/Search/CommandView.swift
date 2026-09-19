import SwiftUI

/// "create a folder for anything related to my bank and put those files in it" —
/// always proposes the matched files and destination before moving anything;
/// see plan.md section 5/6/8.
struct CommandView: View {
    let interpreter: CommandInterpreter
    @State private var instruction: String = ""
    @State private var proposal: ProposedAction?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tell Archivist what to organize").font(.headline)
            TextField("e.g. put all my bank files in one folder", text: $instruction, onCommit: propose)
                .textFieldStyle(.roundedBorder)

            if isLoading {
                ProgressView()
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            if let proposal {
                Divider()
                Text("Will create folder \"\(proposal.destinationFolderName)\" and move:")
                    .font(.caption).bold()
                List(proposal.matchedNodes) { node in
                    Text(node.filename).font(.caption)
                }
                .frame(height: 160)

                HStack {
                    Button("Confirm and move") { execute(proposal) }
                    Button("Cancel") { self.proposal = nil }
                }
            }
        }
        .padding()
    }

    private func propose() {
        errorMessage = nil
        proposal = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                proposal = try await interpreter.propose(for: instruction)
            } catch CommandInterpreterError.noMatches {
                errorMessage = "No indexed files matched that."
            } catch {
                errorMessage = "Couldn't interpret that: \(error)"
            }
        }
    }

    private func execute(_ action: ProposedAction) {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        do {
            _ = try interpreter.execute(action, into: downloads)
            proposal = nil
            instruction = ""
        } catch {
            errorMessage = "Move failed: \(error)"
        }
    }
}
