import Foundation
import os

public struct AppRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let prerelease: Bool
    public let draft: Bool

    public init(tagName: String, prerelease: Bool = false, draft: Bool = false) {
        self.tagName = tagName
        self.prerelease = prerelease
        self.draft = draft
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease
        case draft
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
    }
}

public enum AppUpdateResult: Equatable, Sendable {
    case upToDate
    case available(version: String)
    case failed(AppUpdateFailure)
}

// Every failure is reported as such, never as "up to date", and says what the user can do.
public enum AppUpdateFailure: Equatable, Sendable {
    case offline
    case rateLimited
    case badResponse

    public var message: String {
        switch self {
        case .offline:
            return String(localized: "Couldn't check for updates. Check your internet connection.", bundle: Localization.bundle)
        case .rateLimited:
            return String(localized: "GitHub isn't answering more update checks right now. Try again in a while.", bundle: Localization.bundle)
        case .badResponse:
            return String(localized: "Couldn't read the answer from GitHub. Try again later.", bundle: Localization.bundle)
        }
    }
}

public protocol AppReleaseSource: Sendable {
    func latestRelease() async throws -> AppRelease
}

public enum AppUpdateCheck {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/markstrom/sorla/releases/latest")!
    // Fixed, so a tampered response can never choose what the Download button opens.
    public static let downloadPageURL = URL(string: "https://github.com/markstrom/sorla/releases/latest")!

    private static let logger = Logger(subsystem: "com.sorla.app", category: "AppUpdateCheck")

    public static func version(fromTag tag: String) -> SemanticVersion? {
        SemanticVersion(tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag)
    }

    public static func decide(currentVersion: String?, latest: AppRelease) -> AppUpdateResult {
        guard
            !latest.prerelease, !latest.draft,
            let current = currentVersion.flatMap(SemanticVersion.init),
            let newest = version(fromTag: latest.tagName)
        else { return .failed(.badResponse) }
        return newest > current ? .available(version: newest.description) : .upToDate
    }

    public static func check(currentVersion: String?, source: AppReleaseSource) async -> AppUpdateResult {
        do {
            let release = try await source.latestRelease()
            let result = decide(currentVersion: currentVersion, latest: release)
            if result == .failed(.badResponse) {
                logger.error("unusable release: tag=\(release.tagName, privacy: .public) prerelease=\(release.prerelease, privacy: .public) draft=\(release.draft, privacy: .public) current=\(currentVersion ?? "none", privacy: .public)")
            }
            return result
        } catch {
            logger.error("update check failed: \(String(describing: error), privacy: .public)")
            return .failed(failure(for: error))
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
    ]

    // GitHub answers 403 or 429 when the unauthenticated rate limit is used up.
    static func failure(for error: Error) -> AppUpdateFailure {
        if case ModelNetworkError.httpStatus(let status) = error {
            return status == 403 || status == 429 ? .rateLimited : .badResponse
        }
        if let urlError = error as? URLError, offlineCodes.contains(urlError.code) {
            return .offline
        }
        return .badResponse
    }
}

public struct URLSessionAppReleaseSource: AppReleaseSource {
    private let session: URLSession
    private let appVersion: String

    public init(appVersion: String) {
        self.appVersion = appVersion
        session = URLSession(configuration: Self.makeConfiguration())
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        return configuration
    }

    static func makeRequest(appVersion: String) -> URLRequest {
        var request = URLRequest(url: AppUpdateCheck.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("Sorla/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        return request
    }

    static func decode(_ data: Data) throws -> AppRelease {
        try JSONDecoder().decode(AppRelease.self, from: data)
    }

    public func latestRelease() async throws -> AppRelease {
        let (data, response) = try await session.data(for: Self.makeRequest(appVersion: appVersion))
        try URLSessionModelNetwork.checkStatus(response)
        return try Self.decode(data)
    }
}
