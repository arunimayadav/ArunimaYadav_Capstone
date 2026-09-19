import Foundation
import CryptoKit

enum ContentHasher {
    /// SHA-256 of file bytes — the dedup key referenced throughout plan.md sections 6/7.
    static func hash(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
