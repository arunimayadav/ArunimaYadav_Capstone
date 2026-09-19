import Foundation
import Combine

/// Non-secret settings (which provider is preferred, confidence threshold) live in
/// UserDefaults; API keys live in Keychain via KeychainStore. See plan.md section 6/8.
final class SettingsStore: ObservableObject {
    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let preferredProvider = "archivist.preferredProvider"
        static let confidenceThreshold = "archivist.confidenceThreshold"
        static let watchDesktop = "archivist.watchDesktop"
        static let personName = "archivist.personName"
    }

    @Published var preferredProvider: ProviderKind? {
        didSet { defaults.set(preferredProvider?.rawValue, forKey: Keys.preferredProvider) }
    }

    @Published var confidenceThreshold: Double {
        didSet { defaults.set(confidenceThreshold, forKey: Keys.confidenceThreshold) }
    }

    @Published var watchDesktopToo: Bool {
        didSet { defaults.set(watchDesktopToo, forKey: Keys.watchDesktop) }
    }

    /// skills/filename-nomenclature.md: "<PersonName> always comes from config,
    /// never inferred from the file itself." This is that config.
    @Published var personName: String {
        didSet { defaults.set(personName, forKey: Keys.personName) }
    }

    init() {
        if let raw = defaults.string(forKey: Keys.preferredProvider) {
            preferredProvider = ProviderKind(rawValue: raw)
        } else {
            preferredProvider = nil // nil means "use local Ollama"
        }
        let stored = defaults.double(forKey: Keys.confidenceThreshold)
        confidenceThreshold = stored > 0 ? stored : 0.6
        watchDesktopToo = defaults.bool(forKey: Keys.watchDesktop)
        personName = defaults.string(forKey: Keys.personName) ?? ""
    }

    func apiKey(for provider: ProviderKind) -> String? {
        keychain.get(account: provider.rawValue)
    }

    func setAPIKey(_ key: String, for provider: ProviderKind) {
        if key.isEmpty {
            keychain.remove(account: provider.rawValue)
        } else {
            keychain.set(key, account: provider.rawValue)
        }
    }
}
