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

// MARK: - TUI Provider

/// Mirrors DeepSeek-TUI's `ProviderKind` enum.
enum TUIProviderKind: String, CaseIterable, Identifiable, Codable {
    case deepseek
    case nvidiaNim = "nvidia-nim"
    case openai
    case openrouter
    case novita
    case fireworks
    case sglang
    case vllm
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .nvidiaNim: return "NVIDIA NIM"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .novita: return "Novita"
        case .fireworks: return "Fireworks"
        case .sglang: return "SGLang"
        case .vllm: return "vLLM"
        case .ollama: return "Ollama"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com/beta"
        case .nvidiaNim: return "https://integrate.api.nvidia.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .novita: return "https://api.novita.ai/v1"
        case .fireworks: return "https://api.fireworks.ai/inference/v1"
        case .sglang: return "http://localhost:30000/v1"
        case .vllm: return "http://localhost:8000/v1"
        case .ollama: return "http://localhost:11434/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-v4-pro"
        case .nvidiaNim: return "deepseek-ai/deepseek-v4-pro"
        case .openai: return "gpt-4.1"
        case .openrouter: return "deepseek/deepseek-v4-pro"
        case .novita: return "deepseek/deepseek-v4-pro"
        case .fireworks: return "accounts/fireworks/models/deepseek-v4-pro"
        case .sglang: return "deepseek-ai/DeepSeek-V4-Pro"
        case .vllm: return "deepseek-ai/DeepSeek-V4-Pro"
        case .ollama: return "deepseek-coder:1.3b"
        }
    }

    /// Whether this provider typically requires an API key.
    var requiresAuth: Bool {
        switch self {
        case .sglang, .vllm, .ollama: return false
        default: return true
        }
    }
}

// MARK: - Account

struct APIKeyAccount: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var key: String
    var createdAt: Date
    var baseURL: String
    var model: String
    var tuiProvider: TUIProviderKind?

    init(
        id: UUID,
        name: String,
        key: String,
        createdAt: Date,
        baseURL: String? = nil,
        model: String? = nil,
        tuiProvider: TUIProviderKind? = nil
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.createdAt = createdAt
        self.baseURL = baseURL?.trimmedNonEmpty ?? DeepSeekProfilePreset.claudeCodePro1M.baseURL
        self.model = model?.trimmedNonEmpty ?? DeepSeekProfilePreset.claudeCodePro1M.model
        self.tuiProvider = tuiProvider
    }

    enum CodingKeys: String, CodingKey {
        case id, name, key, createdAt, baseURL, model
        case tuiProvider = "tui_provider"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        let model = try container.decodeIfPresent(String.self, forKey: .model)
        let provider = try container.decodeIfPresent(TUIProviderKind.self, forKey: .tuiProvider)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            key: try container.decode(String.self, forKey: .key),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            baseURL: baseURL,
            model: model,
            tuiProvider: provider
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