import Foundation

final class DeepSeekAPI: @unchecked Sendable {
    private let endpoint = URL(string: "https://api.deepseek.com/user/balance")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchBalance(apiKey: String) async throws -> BalanceState {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
            guard let info = decoded.balanceInfos.first else {
                throw APIError.noBalanceInfo
            }
            return BalanceState(
                totalBalance: Double(info.totalBalance),
                grantedBalance: Double(info.grantedBalance),
                toppedUpBalance: Double(info.toppedUpBalance),
                currency: info.currency,
                isAvailable: decoded.isAvailable,
                updatedAt: Date(),
                errorMessage: nil
            )
        case 401:
            throw APIError.invalidKey
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.httpStatus(http.statusCode)
        }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case invalidKey
    case rateLimited
    case httpStatus(Int)
    case noBalanceInfo

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid DeepSeek response."
        case .invalidKey:
            return "API key is invalid."
        case .rateLimited:
            return "Rate limited. Try again later."
        case .httpStatus(let status):
            return "DeepSeek API returned HTTP \(status)."
        case .noBalanceInfo:
            return "No balance info returned."
        }
    }
}
