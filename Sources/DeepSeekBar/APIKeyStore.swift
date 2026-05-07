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
            return "Not configured"
        case .environment:
            return "Environment"
        case .file(let url), .saved(let url):
            return url.lastPathComponent
        case .account(let name):
            return name
        }
    }
}

final class APIKeyStore {
    struct State: Codable {
        var accounts: [APIKeyAccount]
        var activeAccountID: UUID?
    }

    private let fileManager = FileManager.default

    private var supportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepSeekBar", isDirectory: true)
    }

    private var savedKeyURL: URL {
        supportDirectory.appendingPathComponent("api_key")
    }

    private var accountsURL: URL {
        supportDirectory.appendingPathComponent("api_keys.json")
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
        if let data = try? Data(contentsOf: accountsURL),
           let state = try? JSONDecoder().decode(State.self, from: data) {
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
        try saveState(state)
    }

    func updateAccount(id: UUID, name: String, baseURL: String, model: String) throws {
        var state = loadState()
        guard let index = state.accounts.firstIndex(where: { $0.id == id }) else {
            return
        }

        let current = state.accounts[index]
        state.accounts[index] = APIKeyAccount(
            id: current.id,
            name: name.trimmedNonEmpty ?? current.displayName,
            key: current.key,
            createdAt: current.createdAt,
            baseURL: baseURL.trimmedNonEmpty ?? DeepSeekProfilePreset.claudeCodePro1M.baseURL,
            model: model.trimmedNonEmpty ?? DeepSeekProfilePreset.claudeCodePro1M.model
        )
        try saveState(state)
    }

    func applyPreset(_ preset: DeepSeekProfilePreset, to id: UUID) throws {
        var state = loadState()
        guard let index = state.accounts.firstIndex(where: { $0.id == id }) else {
            return
        }

        let current = state.accounts[index]
        state.accounts[index] = APIKeyAccount(
            id: current.id,
            name: current.name,
            key: current.key,
            createdAt: current.createdAt,
            baseURL: preset.baseURL,
            model: preset.model
        )
        try saveState(state)
    }

    func clearSavedKey() throws {
        var state = loadState()
        if let active = activeAccount(in: state) {
            state.accounts.removeAll { $0.id == active.id }
            state.activeAccountID = state.accounts.first?.id
            try saveState(state)
        }
        if fileManager.fileExists(atPath: savedKeyURL.path), state.accounts.isEmpty {
            try? fileManager.removeItem(at: savedKeyURL)
        }
    }

    private func saveState(_ state: State) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(normalized(state))
        try data.write(to: accountsURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: accountsURL.path)
    }

    private func normalized(_ state: State) -> State {
        let accounts = state.accounts
            .filter { $0.key.trimmedNonEmpty != nil }
            .map {
                APIKeyAccount(
                    id: $0.id,
                    name: $0.name,
                    key: $0.key,
                    createdAt: $0.createdAt,
                    baseURL: $0.baseURL,
                    model: $0.model
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
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        return cleaned
    }
}
