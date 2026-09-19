import SwiftUI

/// Settings menu: pick a provider, enter its API key (stored in Keychain via
/// SettingsStore), or leave everything unset to stay on local-only Ollama.
/// See plan.md section 2/6/8.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var keyDrafts: [ProviderKind: String] = [:]

    var body: some View {
        // Scrollable rather than height-unconstrained — see ContentView's note on
        // why every tab needs to fit inside one fixed popover size.
        ScrollView {
            Form {
                Section("AI Provider") {
                    Picker("Preferred provider", selection: Binding(
                        get: { settings.preferredProvider ?? .ollama },
                        set: { settings.preferredProvider = $0 == .ollama ? nil : $0 }
                    )) {
                        ForEach(ProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    Text("Local Ollama is always the fallback if a cloud provider isn't configured or a call fails.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("API Keys (stored in Keychain)") {
                    ForEach(ProviderKind.allCases.filter { $0.requiresAPIKey }) { kind in
                        HStack {
                            Text(kind.displayName)
                                .frame(width: 110, alignment: .leading)
                            SecureField("API key", text: Binding(
                                get: { keyDrafts[kind] ?? settings.apiKey(for: kind) ?? "" },
                                set: { keyDrafts[kind] = $0 }
                            ))
                            Button("Save") {
                                settings.setAPIKey(keyDrafts[kind] ?? "", for: kind)
                            }
                        }
                    }
                    Link("Get a Groq key", destination: URL(string: "https://console.groq.com/keys")!)
                        .font(.caption)
                }

                Section("Watching") {
                    Toggle("Also watch Desktop", isOn: $settings.watchDesktopToo)
                    HStack {
                        Text("Confidence threshold")
                        Slider(value: $settings.confidenceThreshold, in: 0...1, step: 0.05)
                        Text(String(format: "%.2f", settings.confidenceThreshold))
                            .frame(width: 40)
                    }
                }
            }
            .padding()
        }
    }
}
