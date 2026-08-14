import Foundation

struct BalanceState: Equatable {
    var totalBalance: Double?
    var grantedBalance: Double?
    var toppedUpBalance: Double?
    var currency: String = "CNY"
    var isAvailable: Bool = false
    var updatedAt: Date?
    var errorMessage: String?

    var hasBalance: Bool {
        totalBalance != nil
    }
}

/// Official DeepSeek model catalog (per api-docs.deepseek.com/quick_start/pricing).
/// Both models expose 1M context; there is no "[1m]" model-name variant.
/// Passing an unsupported model name to the Anthropic API silently maps to
/// deepseek-v4-flash, so presets must never invent model identifiers.
enum DeepSeekOfficialModel {
    static let pro = "deepseek-v4-pro"
    static let flash = "deepseek-v4-flash"

    /// All officially supported model identifiers.
    static let all: Set<String> = [pro, flash]

    static func isOfficial(_ model: String) -> Bool {
        all.contains(model.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Account

/// An API key account. The key itself lives in the Keychain
/// (service "com.deepseekbar.app", account = account UUID) and is restored
/// here on decode; the JSON on disk holds metadata only.
/// (Legacy "tui_provider"/"baseURL"/"model" keys in old state files are ignored.)
struct APIKeyAccount: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var key: String
    var createdAt: Date

    init(id: UUID, name: String, key: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.key = key
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let key = AppKeychainStore.get(account: id.uuidString) ?? ""
        self.init(
            id: id,
            name: try container.decode(String.self, forKey: .name),
            key: key,
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        )
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Key" : trimmed
    }

    var maskedKey: String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else {
            return "••••"
        }
        return "\(trimmed.prefix(6))…\(trimmed.suffix(4))"
    }

}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

extension Double {
    /// Formats a balance amount using the currency returned by the official
    /// balance API ("CNY" | "USD") instead of a hard-coded symbol.
    func moneyText(currency: String = "CNY") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "\(currency) \(self)"
    }

    /// Menu-bar-friendly short form: whole yuan above 100, two decimals below.
    var compactMoneyText: String {
        if self >= 100 { return String(format: "%.0f", self) }
        return String(format: "%.2f", self)
    }
}