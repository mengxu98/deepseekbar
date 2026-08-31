import Foundation

enum APIKeySource: Equatable {
    case none
    case environment
    case file(URL)
    case saved(URL)
    case account(String)

    var label: String {
        switch self {
        case .none:
            return L10n.tr("Not configured")
        case .environment:
            return L10n.tr("Environment")
        case .file(let url), .saved(let url):
            return url.lastPathComponent
        case .account(let name):
            return name
        }
    }
}

/// Abstraction over the Keychain so APIKeyStore is testable with an
/// in-memory store; production uses the SecItem implementation.
protocol KeychainStoring {
    func set(_ key: String, account: String) throws
    func get(account: String) -> String?
    func delete(account: String)
}

final class APIKeyStore {
    struct State: Codable {
        var accounts: [APIKeyAccount]
        var activeAccountID: UUID?
    }

    private let fileManager: FileManager
    private let keychain: KeychainStoring
    private let baseDirectory: URL

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        keychain: KeychainStoring = AppKeychainStore()
    ) {
        self.fileManager = fileManager
        self.keychain = keychain
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DeepSeekBar", isDirectory: true)
        }
    }

    private var savedKeyURL: URL {
        baseDirectory.appendingPathComponent("api_key")
    }

    private var accountsURL: URL {
        baseDirectory.appendingPathComponent("api_keys.json")
    }

    private var candidateURLs: [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            savedKeyURL,
            home.appendingPathComponent(".deepseek/api_key"),
            home.appendingPathComponent(".deepseek/config"),
            home.appendingPathComponent(".config/deepseek/config")
        ]
    }

    func load() -> (key: String?, source: APIKeySource) {
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.trimmedNonEmpty {
            return (env, .environment)
        }

        let state = loadState()
        if let active = activeAccount(in: state) {
            return (active.key, .account(active.displayName))
        }

        for url in candidateURLs {
            guard let key = try? String(contentsOf: url, encoding: .utf8).trimmedNonEmpty else {
                continue
            }
            return (key, url == savedKeyURL ? .saved(url) : .file(url))
        }

        return (nil, .none)
    }

    func loadState() -> State {
        migrateLegacyKeysIfNeeded()

        if let data = try? Data(contentsOf: accountsURL),
           var state = try? JSONDecoder().decode(State.self, from: data) {
            for index in state.accounts.indices {
                let account = state.accounts[index]
                state.accounts[index].key = keychain.get(account: account.id.uuidString) ?? account.key
            }
            return normalized(state)
        }

        if let legacy = try? String(contentsOf: savedKeyURL, encoding: .utf8).trimmedNonEmpty {
            let account = APIKeyAccount(
                id: UUID(),
                name: "Default",
                key: legacy,
                createdAt: Date()
            )
            let state = State(accounts: [account], activeAccountID: account.id)
            try? saveState(state)
            return state
        }

        return State(accounts: [], activeAccountID: nil)
    }

    func activeAccount(in state: State? = nil) -> APIKeyAccount? {
        let state = state ?? loadState()
        if let activeAccountID = state.activeAccountID,
           let account = state.accounts.first(where: { $0.id == activeAccountID }) {
            return account
        }
        return state.accounts.first
    }

    func save(_ key: String) throws {
        try addAccount(name: "Default", key: key)
    }

    @discardableResult
    func addAccount(name: String, key: String) throws -> APIKeyAccount {
        let cleaned = try cleanedKey(key)
        var state = loadState()
        guard Self.containsKey(cleaned, in: state) == false else {
            throw APIKeyStoreError.duplicateKey
        }
        let account = APIKeyAccount(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty ?? "Key \(state.accounts.count + 1)",
            key: cleaned,
            createdAt: Date()
        )
        state.accounts.append(account)
        state.activeAccountID = account.id
        try saveState(state)
        return account
    }

    static func containsKey(_ key: String, in state: State) -> Bool {
        let cleaned = key.trimmedNonEmpty
        return state.accounts.contains { $0.key.trimmedNonEmpty == cleaned }
    }

    func setActiveAccount(id: UUID) throws {
        var state = loadState()
        guard state.accounts.contains(where: { $0.id == id }) else {
            return
        }
        state.activeAccountID = id
        try saveState(state)
    }

    func removeAccount(id: UUID) throws {
        var state = loadState()
        state.accounts.removeAll { $0.id == id }
        if state.activeAccountID == id {
            state.activeAccountID = state.accounts.first?.id
        }
        keychain.delete(account: id.uuidString)
        try saveState(state)
    }

    func updateAccount(id: UUID, name: String) throws {
        var state = loadState()
        guard let index = state.accounts.firstIndex(where: { $0.id == id }) else {
            return
        }

        let current = state.accounts[index]
        state.accounts[index] = APIKeyAccount(
            id: current.id,
            name: name.trimmedNonEmpty ?? current.displayName,
            key: current.key,
            createdAt: current.createdAt
        )
        try saveState(state)
    }

    func clearSavedKey() throws {
        var state = loadState()
        if let active = activeAccount(in: state) {
            keychain.delete(account: active.id.uuidString)
            state.accounts.removeAll { $0.id == active.id }
            state.activeAccountID = state.accounts.first?.id
            try saveState(state)
        }
        if fileManager.fileExists(atPath: savedKeyURL.path), state.accounts.isEmpty {
            try? fileManager.removeItem(at: savedKeyURL)
        }
    }

    // MARK: - Private

    private func saveState(_ state: State) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        // 1. Secrets live in the Keychain only. APIKeyAccount's CodingKeys
        //    omit `key`, so the JSON below holds metadata exclusively.
        for account in state.accounts {
            try keychain.set(account.key, account: account.id.uuidString)
        }

        try saveMetadata(normalized(state))
    }

    private func saveMetadata(_ state: State) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: accountsURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: accountsURL.path)
    }

    /// One-time migration: older builds stored plaintext keys inside
    /// api_keys.json. Move those into the Keychain, then rewrite the file
    /// with metadata only.
    private func migrateLegacyKeysIfNeeded() {
        guard let data = try? Data(contentsOf: accountsURL) else { return }

        guard let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        let plaintextKeys = state.accounts.filter { $0.key.trimmedNonEmpty != nil }
        guard !plaintextKeys.isEmpty else { return }

        do {
            for account in plaintextKeys {
                try keychain.set(account.key, account: account.id.uuidString)
            }
            // Rewrite metadata without calling saveState: accounts already
            // backed only by Keychain must never be overwritten with "".
            try saveMetadata(state)
        } catch {
            return
        }
    }

    private func normalized(_ state: State) -> State {
        let accounts = state.accounts
            .filter { $0.key.trimmedNonEmpty != nil }
            .map {
                APIKeyAccount(
                    id: $0.id,
                    name: $0.name,
                    key: $0.key,
                    createdAt: $0.createdAt
                )
            }
        let activeID = state.activeAccountID.flatMap { id in
            accounts.contains(where: { $0.id == id }) ? id : nil
        }
        return State(accounts: accounts, activeAccountID: activeID ?? accounts.first?.id)
    }

    private func cleanedKey(_ key: String) throws -> String {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else {
            throw APIKeyStoreError.emptyKey
        }
        return cleaned
    }
}

enum APIKeyStoreError: LocalizedError {
    case emptyKey
    case duplicateKey

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return L10n.tr("API key must not be empty.")
        case .duplicateKey:
            return L10n.tr("This API key is already saved.")
        }
    }
}
