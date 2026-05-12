import AppKit
import Foundation

struct AppUpdateInfo {
    let currentVersion: String
    let latestVersion: String
    let releaseName: String
    let releaseURL: URL
}

enum AppUpdateState {
    case idle
    case checking
    case upToDate(checkedVersion: String)
    case available(AppUpdateInfo)
    case failed(String)
}

struct AppUpdateChecker {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    private let latestReleaseURL: URL
    private let session: URLSession

    init(
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/mengxu98/deepseekbar/releases/latest")!,
        session: URLSession = .shared
    ) {
        self.latestReleaseURL = latestReleaseURL
        self.session = session
    }

    var currentVersion: String {
        let rawVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let trimmed = rawVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : "0.0.0"
    }

    func check() async throws -> AppUpdateInfo? {
        var request = URLRequest(url: configuredLatestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("deepseekbar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.unexpectedStatus(httpResponse.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard release.draft == false, release.prerelease == false else {
            return nil
        }

        let latestVersion = Self.normalizedVersion(release.tagName)
        let currentVersion = Self.normalizedVersion(currentVersion)
        guard Self.compareVersions(latestVersion, currentVersion) == .orderedDescending else {
            return nil
        }

        return AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseName: release.name ?? release.tagName,
            releaseURL: release.htmlURL
        )
    }

    private var configuredLatestReleaseURL: URL {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "DeepSeekBarGitHubLatestReleaseURL") as? String,
              let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return latestReleaseURL
        }
        return url
    }

    private static func normalizedVersion(_ version: String) -> String {
        version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .trimmingPrefix("V")
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}

enum UpdateCheckError: LocalizedError {
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            return "GitHub returned HTTP \(status)."
        }
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
