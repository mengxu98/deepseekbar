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

struct UsageEstimate: Equatable {
    var todayUsed: Double = 0
    var monthUsed: Double = 0
    var todayBudget: Double?
    var monthBudget: Double?
}

enum DeepSeekProfilePreset: String, CaseIterable, Identifiable {
    case claudeCodePro1M
    case pro
    case flash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCodePro1M:
            return "deepseek-v4-pro[1m]"
        case .pro:
            return "deepseek-v4-pro"
        case .flash:
            return "deepseek-v4-flash"
        }
    }

    var shortTitle: String {
        switch self {
        case .claudeCodePro1M:
            return "Pro 1M"
        case .pro:
            return "Pro"
        case .flash:
            return "Flash"
        }
    }

    var baseURL: String {
        "https://api.deepseek.com/anthropic"
    }

    var model: String {
        switch self {
        case .claudeCodePro1M:
            return "deepseek-v4-pro[1m]"
        case .pro:
            return "deepseek-v4-pro"
        case .flash:
            return "deepseek-v4-flash"
        }
    }

    var detail: String {
        switch self {
        case .claudeCodePro1M:
            return "deepseek-v4-pro[1m] · 1M context"
        case .pro:
            return "deepseek-v4-pro · 1M context"
        case .flash:
            return "deepseek-v4-flash · 1M context"
        }
    }
}

struct APIKeyAccount: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var key: String
    var createdAt: Date
    var baseURL: String
    var model: String

    init(
        id: UUID,
        name: String,
        key: String,
        createdAt: Date,
        baseURL: String = DeepSeekProfilePreset.claudeCodePro1M.baseURL,
        model: String = DeepSeekProfilePreset.claudeCodePro1M.model
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.createdAt = createdAt
        self.baseURL = baseURL.trimmedNonEmpty ?? DeepSeekProfilePreset.claudeCodePro1M.baseURL
        self.model = model.trimmedNonEmpty ?? DeepSeekProfilePreset.claudeCodePro1M.model
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case key
        case createdAt
        case baseURL
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            key: try container.decode(String.self, forKey: .key),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            baseURL: try container.decodeIfPresent(String.self, forKey: .baseURL) ?? DeepSeekProfilePreset.claudeCodePro1M.baseURL,
            model: try container.decodeIfPresent(String.self, forKey: .model) ?? DeepSeekProfilePreset.claudeCodePro1M.model
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

    var compactModelText: String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedModel.isEmpty ? DeepSeekProfilePreset.claudeCodePro1M.model : trimmedModel
    }

    var modelDetailText: String {
        if let preset = DeepSeekProfilePreset.allCases.first(where: { $0.model == compactModelText }) {
            return preset.detail
        }
        return "\(compactModelText) · \(baseURL)"
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
    var moneyText: String {
        "¥ " + String(format: "%.2f", self)
    }
}
