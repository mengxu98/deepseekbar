import Foundation

/// Represents a single provider entry parsed from DeepSeek-TUI's config.toml.
struct TUIProviderConfig: Equatable {
    var apiKey: String?
    var baseURL: String?
    var model: String?
}

/// Reads and writes DeepSeek-TUI's `~/.deepseek/config.toml` provider sections.
/// Only modifies `[providers.<name>]` blocks; other TOML content is preserved.
enum DeepSeekTUIConfig {
    private static let fileManager = FileManager.default

    static var configURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".deepseek/config.toml")
    }

    // MARK: - Read

    /// Returns all provider configs found in the TOML file.
    static func loadProviders() -> [String: TUIProviderConfig] {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return [:]
        }
        return parseProviders(from: content)
    }

    /// Returns the provider config for a specific name, if present.
    static func loadProvider(named name: String) -> TUIProviderConfig? {
        loadProviders()[name]
    }

    // MARK: - Write

    /// Saves or updates a provider's config in the TOML file.
    /// Creates the file and directory if they don't exist.
    static func saveProvider(
        named name: String,
        apiKey: String?,
        baseURL: String? = nil,
        model: String? = nil
    ) throws {
        var providers = loadProviders()
        providers[name] = TUIProviderConfig(apiKey: apiKey, baseURL: baseURL, model: model)
        try writeProviders(providers)
    }

    /// Removes a provider section from the TOML file.
    static func removeProvider(named name: String) throws {
        var providers = loadProviders()
        providers.removeValue(forKey: name)
        try writeProviders(providers)
    }

    /// Sets (or clears) the API key for a provider, preserving other fields.
    static func setAPIKey(_ key: String?, forProvider name: String) throws {
        var providers = loadProviders()
        if var existing = providers[name] {
            existing.apiKey = key
            providers[name] = existing
        } else if let key {
            providers[name] = TUIProviderConfig(apiKey: key)
        }
        try writeProviders(providers)
    }

    // MARK: - Private

    private static func parseProviders(from toml: String) -> [String: TUIProviderConfig] {
        var result: [String: TUIProviderConfig] = [:]
        var currentSection: String?

        for line in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Section header: [providers.<name>]
            if trimmed.hasPrefix("[providers.") && trimmed.hasSuffix("]") {
                let inner = String(trimmed.dropFirst(12).dropLast(1))
                    .trimmingCharacters(in: .whitespaces)
                currentSection = inner
                if result[inner] == nil {
                    result[inner] = TUIProviderConfig()
                }
                continue
            }

            // Reset section on non-providers headers
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = nil
                continue
            }

            guard let section = currentSection else { continue }

            // Key = "value"
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let rawValue = parts[1].trimmingCharacters(in: .whitespaces)
            let value = unquote(rawValue)

            switch key {
            case "api_key":
                result[section]?.apiKey = value.isEmpty ? nil : value
            case "base_url":
                result[section]?.baseURL = value.isEmpty ? nil : value
            case "model":
                result[section]?.model = value.isEmpty ? nil : value
            default:
                break
            }
        }

        return result
    }

    private static func writeProviders(_ providers: [String: TUIProviderConfig]) throws {
        // Read existing file to preserve non-provider content
        let existingContent: String
        if let content = try? String(contentsOf: configURL, encoding: .utf8) {
            existingContent = content
        } else {
            existingContent = ""
        }

        let dir = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let newTOML = rebuildTOML(existingContent: existingContent, providers: providers)
        try newTOML.write(to: configURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    /// Rebuilds the TOML content, preserving non-provider sections and comments.
    private static func rebuildTOML(existingContent: String, providers: [String: TUIProviderConfig]) -> String {
        let lines = existingContent.split(separator: "\n", omittingEmptySubsequences: false)
        var outputLines: [String] = []
        var inProvidersSection = false
        var currentProviderName: String?
        var processedProviders = Set<String>()
        var providerSectionBuffer: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[providers.") && trimmed.hasSuffix("]") {
                // Flush previous provider section buffer
                flushProviderSection(
                    name: currentProviderName,
                    buffer: &providerSectionBuffer,
                    providers: providers,
                    processed: &processedProviders,
                    output: &outputLines
                )
                inProvidersSection = true
                currentProviderName = String(trimmed.dropFirst(12).dropLast(1))
                    .trimmingCharacters(in: .whitespaces)
                providerSectionBuffer = [String(line)]
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // Flush any open provider section
                flushProviderSection(
                    name: currentProviderName,
                    buffer: &providerSectionBuffer,
                    providers: providers,
                    processed: &processedProviders,
                    output: &outputLines
                )
                inProvidersSection = false
                currentProviderName = nil
                outputLines.append(String(line))
                continue
            }

            if inProvidersSection {
                providerSectionBuffer.append(String(line))
            } else {
                outputLines.append(String(line))
            }
        }

        // Flush trailing provider section
        flushProviderSection(
            name: currentProviderName,
            buffer: &providerSectionBuffer,
            providers: providers,
            processed: &processedProviders,
            output: &outputLines
        )

        // Append new providers not yet written
        for (name, config) in providers.sorted(by: { $0.key < $1.key }) {
            guard !processedProviders.contains(name) else { continue }
            outputLines.append("")
            outputLines.append("[providers.\(name)]")
            if let key = config.apiKey, !key.isEmpty {
                outputLines.append("api_key = \"\(key)\"")
            }
            if let url = config.baseURL, !url.isEmpty {
                outputLines.append("base_url = \"\(url)\"")
            }
            if let model = config.model, !model.isEmpty {
                outputLines.append("model = \"\(model)\"")
            }
            processedProviders.insert(name)
        }

        return outputLines.joined(separator: "\n") + "\n"
    }

    private static func flushProviderSection(
        name: String?,
        buffer: inout [String],
        providers: [String: TUIProviderConfig],
        processed: inout Set<String>,
        output: inout [String]
    ) {
        guard let name, !buffer.isEmpty else {
            buffer.removeAll()
            return
        }

        if let config = providers[name] {
            // Rewrite this provider section
            output.append("[providers.\(name)]")
            if let key = config.apiKey, !key.isEmpty {
                output.append("api_key = \"\(key)\"")
            }
            if let url = config.baseURL, !url.isEmpty {
                output.append("base_url = \"\(url)\"")
            }
            if let model = config.model, !model.isEmpty {
                output.append("model = \"\(model)\"")
            }
            processed.insert(name)
        } else {
            // Provider removed — omit the section
            // (intentionally skip appending)
        }

        buffer.removeAll()
    }

    // MARK: - Helpers

    private static func unquote(_ value: String) -> String {
        var s = value
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) ||
           (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
        }
        // Unescape basic TOML escapes
        s = s.replacingOccurrences(of: "\\\"", with: "\"")
        s = s.replacingOccurrences(of: "\\n", with: "\n")
        s = s.replacingOccurrences(of: "\\\\", with: "\\")
        return s
    }

    // MARK: - Convenience

    /// All provider names found in the TOML config.
    static func providerNames() -> [String] {
        Array(loadProviders().keys).sorted()
    }
}