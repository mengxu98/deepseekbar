import Foundation

/// Reads and writes DeepSeek-TUI's file-backed secret store.
///
/// DeepSeek-TUI stores secrets in `~/.deepseek/secrets/secrets.json`
/// with the format:
///   {"entries": {"deepseek": "sk-...", "nvidia-nim": "nv-..."}}
///
/// This is the fallback when the OS keyring is not available.
enum SecretsFileStore {
    private static let fileManager = FileManager.default

    private struct SecretsPayload: Codable {
        var entries: [String: String]
    }

    static var secretsURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".deepseek/secrets/secrets.json")
    }

    // MARK: - Read

    /// Returns all entries from the secrets file.
    static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: secretsURL),
              let payload = try? JSONDecoder().decode(SecretsPayload.self, from: data) else {
            return [:]
        }
        return payload.entries
    }

    /// Returns the key for a specific provider, if stored.
    static func get(provider: String) -> String? {
        loadAll()[provider]
    }

    // MARK: - Write

    /// Sets or updates a key for a provider.
    static func set(_ key: String, provider: String) throws {
        var entries = loadAll()
        entries[provider] = key
        try save(entries)
    }

    /// Removes a provider's key.
    static func delete(provider: String) throws {
        var entries = loadAll()
        entries.removeValue(forKey: provider)
        try save(entries)
    }

    /// Checks if the secrets file exists.
    static func fileExists() -> Bool {
        fileManager.fileExists(atPath: secretsURL.path)
    }

    // MARK: - Private

    private static func save(_ entries: [String: String]) throws {
        let dir = secretsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let payload = SecretsPayload(entries: entries)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: secretsURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
    }
}
