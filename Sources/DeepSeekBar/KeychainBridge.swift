import Foundation

/// Bridges macOS Keychain access for DeepSeek-TUI keys.
///
/// DeepSeek-TUI stores provider API keys in the macOS Keychain under:
///   Service: "deepseek"
///   Account:  provider name (e.g. "deepseek", "nvidia-nim")
///
/// Uses `security` CLI for add/delete/find operations.
enum KeychainBridge {
    private static let service = "deepseek"

    // MARK: - Read

    /// Reads a key from the Keychain for the given provider.
    /// Returns nil if no entry exists or if the keychain is unavailable.
    static func get(account: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", service,
            "-a", account,
            "-w"
        ]
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Write

    /// Stores or updates a key in the Keychain for the given provider.
    static func set(_ key: String, account: String) throws {
        // Remove existing entry first
        delete(account: account)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password",
            "-s", service,
            "-a", account,
            "-w", key,
            "-U"  // update if exists
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw KeychainError.addFailed(account: account)
        }
    }

    // MARK: - Delete

    /// Removes a key from the Keychain for the given provider.
    /// No error if the entry does not exist.
    static func delete(account: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "delete-generic-password",
            "-s", service,
            "-a", account
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()
        // Ignore errors — entry may not exist
    }

    // MARK: - List

    /// Returns all account names stored in the Keychain for the DeepSeek service.
    static func listAccounts() -> [String] {
        // We can't easily enumerate keychain entries generically with `security`,
        // but we can check known provider names.
        let knownProviders = [
            "deepseek", "nvidia-nim", "openai", "openrouter",
            "novita", "fireworks", "sglang", "vllm", "ollama"
        ]
        return knownProviders.filter { get(account: $0) != nil }
    }
}

enum KeychainError: LocalizedError {
    case addFailed(account: String)

    var errorDescription: String? {
        switch self {
        case .addFailed(let account):
            return "Failed to save API key for '\(account)' to Keychain."
        }
    }
}
