import XCTest
@testable import SorlaCore

private struct FakeAppReleaseSource: AppReleaseSource {
    let result: Result<AppRelease, Error>

    func latestRelease() async throws -> AppRelease {
        try result.get()
    }
}

final class AppUpdateCheckTests: XCTestCase {
    func testNewerVersionIsAvailable() {
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.0.0", latest: AppRelease(tagName: "v1.0.1")), .available(version: "1.0.1"))
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.0.0", latest: AppRelease(tagName: "1.1.0")), .available(version: "1.1.0"))
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.9.0", latest: AppRelease(tagName: "v1.10.0")), .available(version: "1.10.0"))
    }

    func testSameVersionIsUpToDate() {
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.0.0", latest: AppRelease(tagName: "v1.0.0")), .upToDate)
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.0.0", latest: AppRelease(tagName: "1.0")), .upToDate)
    }

    func testOlderPublishedVersionIsUpToDate() {
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.2.0", latest: AppRelease(tagName: "v1.1.9")), .upToDate)
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.2.0", latest: AppRelease(tagName: "1.0.0")), .upToDate)
    }

    func testMalformedTagIsInvalid() {
        for tag in ["", "v", "latest", "v1.x", "1.0.0-beta.1", "vv1.0.0", "1.0.0.0"] {
            XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.0.0", latest: AppRelease(tagName: tag)), .failed(.badResponse), tag)
        }
    }

    func testMissingOrMalformedCurrentVersionIsInvalid() {
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: nil, latest: AppRelease(tagName: "v1.0.1")), .failed(.badResponse))
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "dev", latest: AppRelease(tagName: "v1.0.1")), .failed(.badResponse))
    }

    func testPrereleasesAndDraftsAreRejected() {
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.0.0", latest: AppRelease(tagName: "v2.0.0", prerelease: true)), .failed(.badResponse))
        XCTAssertEqual(AppUpdateCheck.decide(currentVersion: "1.0.0", latest: AppRelease(tagName: "v2.0.0", draft: true)), .failed(.badResponse))
    }

    func testDecodesOnlyWhatItNeedsFromGitHub() throws {
        let json = #"{"tag_name":"v1.0.1","name":"Sorla 1.0.1","prerelease":false,"draft":false,"html_url":"https://example.com/elsewhere","assets":[]}"#
        XCTAssertEqual(try URLSessionAppReleaseSource.decode(Data(json.utf8)), AppRelease(tagName: "v1.0.1"))
        XCTAssertEqual(try URLSessionAppReleaseSource.decode(Data(#"{"tag_name":"1.2.0"}"#.utf8)), AppRelease(tagName: "1.2.0"))
        XCTAssertEqual(
            try URLSessionAppReleaseSource.decode(Data(#"{"tag_name":"v3.0.0","prerelease":true,"draft":true}"#.utf8)),
            AppRelease(tagName: "v3.0.0", prerelease: true, draft: true)
        )
    }

    func testDecodingFailsWithoutATag() {
        for body in ["", "not json", #"{"message":"Not Found"}"#, #"{"tag_name":42}"#, "[]"] {
            XCTAssertThrowsError(try URLSessionAppReleaseSource.decode(Data(body.utf8)), body)
        }
    }

    func testRequestAsksGitHubForTheLatestReleaseOnly() throws {
        let request = URLSessionAppReleaseSource.makeRequest(appVersion: "1.0.0")

        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/markstrom/sorla/releases/latest")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.allHTTPHeaderFields, [
            "User-Agent": "Sorla/1.0.0",
            "Accept": "application/vnd.github+json",
            "Accept-Language": "en",
        ])
    }

    func testSessionKeepsNoCookiesCacheOrCredentials() {
        let configuration = URLSessionAppReleaseSource.makeConfiguration()

        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
    }

    func testDownloadPageIsFixed() {
        XCTAssertEqual(AppUpdateCheck.downloadPageURL.absoluteString, "https://github.com/markstrom/sorla/releases/latest")
    }

    func testCheckReportsTheDecisionFromTheSource() async {
        let source = FakeAppReleaseSource(result: .success(AppRelease(tagName: "v1.0.1")))
        let result = await AppUpdateCheck.check(currentVersion: "1.0.0", source: source)
        XCTAssertEqual(result, .available(version: "1.0.1"))
    }

    func testOfflineIsReportedAsOfflineNotUpToDate() async {
        for code in [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost] {
            let source = FakeAppReleaseSource(result: .failure(URLError(code)))
            let result = await AppUpdateCheck.check(currentVersion: "1.0.0", source: source)
            XCTAssertEqual(result, .failed(.offline), "\(code)")
        }
    }

    func testRateLimitIsReportedAsRateLimitedNotUpToDate() async {
        for status in [403, 429] {
            let source = FakeAppReleaseSource(result: .failure(ModelNetworkError.httpStatus(status)))
            let result = await AppUpdateCheck.check(currentVersion: "1.0.0", source: source)
            XCTAssertEqual(result, .failed(.rateLimited), "\(status)")
        }
    }

    func testServerErrorsAndOddResponsesAreBadResponses() async {
        let errors: [Error] = [ModelNetworkError.httpStatus(404), ModelNetworkError.httpStatus(502), URLError(.badServerResponse)]
        for error in errors {
            let source = FakeAppReleaseSource(result: .failure(error))
            let result = await AppUpdateCheck.check(currentVersion: "1.0.0", source: source)
            XCTAssertEqual(result, .failed(.badResponse), "\(error)")
        }
    }

    func testGitHubRateLimitStatusBecomesAnError() {
        let url = AppUpdateCheck.latestReleaseURL
        for status in [403, 429] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["X-RateLimit-Remaining": "0"])
            XCTAssertThrowsError(try URLSessionModelNetwork.checkStatus(response)) { error in
                XCTAssertEqual(error as? ModelNetworkError, .httpStatus(status))
            }
        }
    }

    func testEveryFailureHasItsOwnMessage() {
        let messages = Set([AppUpdateFailure.offline, .rateLimited, .badResponse].map(\.message))
        XCTAssertEqual(messages.count, 3)
    }

    func testCheckTreatsADecodingFailureAsInvalid() async {
        let source = FakeAppReleaseSource(result: Result { try URLSessionAppReleaseSource.decode(Data("<html>".utf8)) })
        let result = await AppUpdateCheck.check(currentVersion: "1.0.0", source: source)
        XCTAssertEqual(result, .failed(.badResponse))
    }
}
