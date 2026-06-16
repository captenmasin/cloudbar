import Foundation
import Testing
@testable import CloudBar

@Test func appVersionReadsBundledInfoPlist() {
    #expect(AppVersion.shortVersion == "0.1.0")
    #expect(AppVersion.build == "1")
    #expect(AppVersion.displayString == "Version 0.1.0 (1)")
}

@Test func usageDecodesResourcesAndNestedApplicationClusters() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)

    #expect(usage.data.resources?.databases.map(\.title) == ["Primary database", "Other database"])
    #expect(usage.data.resources?.caches.map(\.title) == ["redis", "other-redis"])
    #expect(usage.data.resources?.buckets.map(\.title) == ["assets", "other-assets"])
    #expect(usage.data.resources?.websockets.map(\.title) == ["realtime", "other-realtime"])

    let application = try #require(usage.data.applicationTotals?.applications.first)
    #expect(application.title == "sitepulse")
    #expect(application.applicationName == "Site Pulse")
    #expect(application.children.count == 2)
    #expect(application.flattened.map(\.title).contains("web"))
    #expect(application.flattened.map(\.title).contains("emails"))
}

@Test func usageDecodesEnvironmentScopedApplicationCompute() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: environmentUsageFixture)

    let computeItems = try #require(usage.data.environmentUsage?.computeItems)
    let groups = Dictionary(grouping: computeItems, by: \.clusterType)

    #expect(groups[.appClusters]?.count == 1)
    #expect(groups[.appClusters]?.first?.totalCostCents == 322)
    #expect(groups[.managedQueues]?.count == 1)
    #expect(groups[.managedQueues]?.first?.totalCostCents == 7)
}

@MainActor
@Test func viewModelFiltersByApplicationAndGroupsClusters() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let applications = try JSONDecoder.laravelCloud.decode(ApplicationsResponse.self, from: applicationsFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage
    viewModel.applications = applications.data
    viewModel.selectedApplicationID = "app-1"

    #expect(viewModel.applicationOptions == [ApplicationOption(id: "app-1", name: "Site Pulse")])
    #expect(viewModel.selectedApplication?.deployURL?.absoluteString == "https://cloud.laravel.com/applications/app-1/deployments")
    #expect(viewModel.selectedApplication?.visitURL?.absoluteString == "https://sitepulse.test")
    #expect(viewModel.selectedApplication?.repositoryURL?.absoluteString == "https://github.com/acme/sitepulse")
    #expect(viewModel.billingPeriodText?.contains("Billing period") == true)
    #expect(viewModel.billingPeriodText?.contains("2026") == true)
    #expect(viewModel.formattedUpdatedAt?.contains("2026") == true)
    #expect(viewModel.displayedCurrentSpendCents == 1275)
    #expect(viewModel.displayedBandwidth == nil)
    #expect(viewModel.displayedApplicationTotalCents == 700)
    #expect(viewModel.displayedDatabaseItems.map(\.title) == ["Primary database"])
    #expect(viewModel.displayedCacheItems.map(\.title) == ["redis"])
    #expect(viewModel.displayedBucketItems.map(\.title) == ["assets"])
    #expect(viewModel.displayedWebSocketItems.map(\.title) == ["realtime"])
    #expect(viewModel.displayedResourcesTotalCents == 450)
    #expect(viewModel.displayedAddonItems.map(\.name) == ["Insights"])
    #expect(viewModel.displayedAddonsTotalCents == 125)

    let groups = Dictionary(uniqueKeysWithValues: viewModel.clusterGroups.map { ($0.0, $0.1.map(\.title)) })
    #expect(groups[.appClusters] == ["web"])
    #expect(groups[.managedQueues] == ["emails"])
}

@MainActor
@Test func viewModelShowsOrganizationTotalsWithoutApplicationFilter() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage

    #expect(viewModel.displayedCurrentSpendCents == 1234)
    #expect(viewModel.displayedBandwidth?.costCents == 50)
    #expect(viewModel.displayedApplicationTotalCents == 700)
    #expect(viewModel.displayedResourcesTotalCents == 450)
    #expect(viewModel.displayedAddonItems.map(\.name) == ["Insights", "Other add-on"])
    #expect(viewModel.displayedAddonsTotalCents == 300)
}

@MainActor
@Test func viewModelMenuBarTitleRespectsSpendDisplayToggle() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage

    viewModel.showSpendInMenuBar = true
    #expect(viewModel.menuBarTitle == viewModel.money(1234))

    viewModel.showSpendInMenuBar = false
    #expect(viewModel.menuBarTitle == "")

    viewModel.usage = nil
    viewModel.showSpendInMenuBar = true
    #expect(viewModel.menuBarTitle == "Cloud")

    viewModel.showSpendInMenuBar = false
    #expect(viewModel.menuBarTitle == "")
}

@MainActor
@Test func viewModelDoesNotShowUnmatchedOrgResourcesForSelectedApplication() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let applications = try JSONDecoder.laravelCloud.decode(ApplicationsResponse.self, from: applicationsFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage
    viewModel.applications = applications.data
    viewModel.selectedApplicationID = "app-unmatched"

    #expect(viewModel.displayedDatabaseItems.isEmpty)
    #expect(viewModel.displayedCacheItems.isEmpty)
    #expect(viewModel.displayedBucketItems.isEmpty)
    #expect(viewModel.displayedWebSocketItems.isEmpty)
    #expect(viewModel.displayedResourcesTotalCents == nil)
    #expect(viewModel.displayedCurrentSpendCents == nil)
    #expect(viewModel.displayedBandwidth == nil)
    #expect(viewModel.displayedApplicationTotalCents == nil)
    #expect(viewModel.displayedAddonItems.isEmpty)
    #expect(viewModel.displayedAddonsTotalCents == nil)
}

@MainActor
@Test func viewModelUsesApplicationTotalsForAllApplicationsCompute() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: orgUsageWithEnvironmentUsageFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage

    #expect(viewModel.displayedApplicationComputeTotalCents == 700)
    let groups = Dictionary(uniqueKeysWithValues: viewModel.clusterGroups.map { ($0.0, $0.1.map(\.title)) })
    #expect(groups[.appClusters] == ["web"])
    #expect(groups[.managedQueues] == ["emails"])
}

@MainActor
@Test func dailySpendStoreComputesDailyCostsFromSnapshots() {
    let defaults = UserDefaults(suiteName: "DailySpendStoreTests")!
    defaults.removePersistentDomain(forName: "DailySpendStoreTests")
    let store = DailySpendStore(defaults: defaults)
    let periodKey = "0:2026-06-01T00:00:00Z"
    let scopeKey = ""
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let dayOne = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
    let dayTwo = calendar.date(from: DateComponents(year: 2026, month: 6, day: 11))!
    let dayThree = calendar.date(from: DateComponents(year: 2026, month: 6, day: 12))!

    store.record(periodKey: periodKey, scopeKey: scopeKey, cumulativeCents: 300, on: dayOne, calendar: calendar)
    store.record(periodKey: periodKey, scopeKey: scopeKey, cumulativeCents: 550, on: dayTwo, calendar: calendar)
    store.record(periodKey: periodKey, scopeKey: scopeKey, cumulativeCents: 700, on: dayThree, calendar: calendar)

    let costs = store.dailyCosts(periodKey: periodKey, scopeKey: scopeKey, calendar: calendar)
    #expect(costs.map(\.costCents) == [300, 250, 150])
    #expect(costs.allSatisfy { !$0.hasSegmentedBreakdown })
}

@Test func dailySpendStoreComputesSegmentedDailyCostsFromSnapshots() {
    let defaults = UserDefaults(suiteName: "DailySpendStoreSegmentTests")!
    defaults.removePersistentDomain(forName: "DailySpendStoreSegmentTests")
    let store = DailySpendStore(defaults: defaults)
    let periodKey = "0:2026-06-01T00:00:00Z"
    let scopeKey = ""
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let dayOne = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
    let dayTwo = calendar.date(from: DateComponents(year: 2026, month: 6, day: 11))!

    store.record(
        periodKey: periodKey,
        scopeKey: scopeKey,
        cumulativeCents: 500,
        categoryCents: [.appClusters: 300, .databases: 200],
        on: dayOne,
        calendar: calendar
    )
    store.record(
        periodKey: periodKey,
        scopeKey: scopeKey,
        cumulativeCents: 900,
        categoryCents: [.appClusters: 500, .databases: 400],
        on: dayTwo,
        calendar: calendar
    )

    let costs = store.dailyCosts(periodKey: periodKey, scopeKey: scopeKey, calendar: calendar)
    #expect(costs.map(\.costCents) == [500, 400])
    #expect(costs[0].segments.map(\.category) == [.appClusters, .databases])
    #expect(costs[0].segments.map(\.costCents) == [300, 200])
    #expect(costs[1].segments.map(\.category) == [.appClusters, .databases])
    #expect(costs[1].segments.map(\.costCents) == [200, 200])
}

@MainActor
@Test func viewModelExposesDailyCostEntriesForCurrentScope() throws {
    let defaults = UserDefaults(suiteName: "DailySpendViewModelTests")!
    defaults.removePersistentDomain(forName: "DailySpendViewModelTests")
    let store = DailySpendStore(defaults: defaults)
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient(), dailySpendStore: store)
    viewModel.usage = usage
    viewModel.recordDailySpendSnapshot()

    #expect(viewModel.dailyCostEntries.count == 1)
    #expect(viewModel.dailyCostEntries.first?.costCents == 1234)
    #expect(viewModel.dailyCostEntries.first?.hasSegmentedBreakdown == true)
}

@MainActor
@Test func viewModelExposesBillingAlertProgressData() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage

    #expect(viewModel.billingAlert == nil)

    let alertUsage = Data(
        """
        {
          "data": {
            "summary": {
              "current_spend_cents": 8000,
              "alert": {
                "threshold_cents": 10000,
                "remaining_percentage": 20
              }
            }
          },
          "meta": {
            "currency": "GBP",
            "period": 0
          }
        }
        """
        .utf8
    )

    let alertResponse = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: alertUsage)
    viewModel.usage = alertResponse

    let billingAlert = try #require(viewModel.billingAlert)
    #expect(billingAlert.thresholdText?.contains("100.00") == true)
    #expect(billingAlert.remainingPercentage == 20)
    #expect(billingAlert.consumedFraction == 0.8)
}

@MainActor
@Test func moneyConvertsCentsToDisplayCurrency() async throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(
        client: LaravelCloudClient(),
        exchangeRateClient: FixedExchangeRateClient(rate: 2)
    )
    viewModel.usage = usage
    await viewModel.setDisplayCurrency("USD")
    await viewModel.setDisplayCurrency("CHF")

    #expect(viewModel.convertedCentsToDisplayCurrency(100) == 200)
    #expect(viewModel.convertedCentsToDisplayCurrency(1234) == 2468)
}

@Test func laravelCloudClientFetchUsageDecodesSuccessResponse() async throws {
    let token = "test-token"
    let session = URLSession.mocked(
        statusCode: 200,
        body: usageFixture,
        url: URL(string: "https://cloud.laravel.com/api/usage")!
    )
    let client = LaravelCloudClient(session: session)

    let usage = try await client.fetchUsage(token: token, environment: nil)
    #expect(usage.data.summary.currentSpendCents == 1234)
}

@Test func laravelCloudClientFetchUsageThrowsAPIErrorOnUnauthorized() async throws {
    let session = URLSession.mocked(
        statusCode: 401,
        body: Data(#"{"message":"Unauthorized"}"#.utf8),
        url: URL(string: "https://cloud.laravel.com/api/usage?environment=env-401")!
    )
    let client = LaravelCloudClient(session: session)

    await #expect(throws: LaravelCloudError.self) {
        _ = try await client.fetchUsage(token: "test-token", environment: "env-401")
    }
}

@Test func laravelCloudClientFetchUsageThrowsDecodingErrorOnInvalidJSON() async throws {
    let session = URLSession.mocked(
        statusCode: 200,
        body: Data("not json".utf8),
        url: URL(string: "https://cloud.laravel.com/api/usage?environment=env-json")!
    )
    let client = LaravelCloudClient(session: session)

    await #expect(throws: DecodingError.self) {
        _ = try await client.fetchUsage(token: "test-token", environment: "env-json")
    }
}

@MainActor
@Test func refreshSuccessSetsUsageAndHasToken() async throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let tokenStore = FakeTokenStore(token: "real-token")
    let client = MockLaravelCloudClient()
    client.usageResult = .success(usage)
    client.applicationsResult = .success([])
    let viewModel = UsageViewModel(client: client, keychain: tokenStore)

    await viewModel.refresh()

    #expect(viewModel.usage != nil)
    #expect(viewModel.errorMessage == nil)
    #expect(viewModel.hasToken == true)
}

@MainActor
@Test func refresh401ClearsUsageAndTracksStatusCode() async throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let tokenStore = FakeTokenStore(token: "real-token")
    let client = MockLaravelCloudClient()
    client.usageResult = .failure(LaravelCloudError.api(statusCode: 401, message: "Unauthorized"))
    let viewModel = UsageViewModel(client: client, keychain: tokenStore)
    viewModel.usage = usage

    await viewModel.refresh()

    #expect(viewModel.usage == nil)
    #expect(viewModel.lastAPIStatusCode == 401)
    #expect(viewModel.errorMessage != nil)
}

@MainActor
@Test func refreshTransientErrorRetainsPreviousUsage() async throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let tokenStore = FakeTokenStore(token: "real-token")
    let client = MockLaravelCloudClient()
    client.usageResult = .failure(URLError(.timedOut))
    let viewModel = UsageViewModel(client: client, keychain: tokenStore)
    viewModel.usage = usage

    await viewModel.refresh()

    #expect(viewModel.usage != nil)
    #expect(viewModel.errorMessage != nil)
}

@MainActor
@Test func saveTokenRejectsMaskedPlaceholder() async throws {
    let tokenStore = FakeTokenStore()
    let viewModel = UsageViewModel(client: MockLaravelCloudClient(), keychain: tokenStore)
    await viewModel.saveToken("abcd...wxyz")

    #expect(viewModel.hasToken == false)
    #expect(tokenStore.storedToken == nil)
    #expect(viewModel.errorMessage != nil)
}

@MainActor
@Test func saveTokenRejectsMaskedValueAfterRealTokenWasSaved() async throws {
    let tokenStore = FakeTokenStore()
    let viewModel = UsageViewModel(client: MockLaravelCloudClient(), keychain: tokenStore)
    await viewModel.saveToken("realtokenvalue1234")
    let originalToken = tokenStore.storedToken
    await viewModel.saveToken(viewModel.maskedToken)

    #expect(tokenStore.storedToken == originalToken)
    #expect(viewModel.errorMessage != nil)
}

@MainActor
@Test func moneyUsesBillingCurrencyWhenExchangeRateUnavailable() async throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(
        client: MockLaravelCloudClient(),
        exchangeRateClient: FailingExchangeRateClient()
    )
    viewModel.usage = usage
    await viewModel.setDisplayCurrency("USD")
    await viewModel.setDisplayCurrency("CHF")

    #expect(viewModel.exchangeRateUnavailable == true)
    #expect(viewModel.convertedCentsToDisplayCurrency(1234) == 1234)
}

@MainActor
@Test func viewModelFallsBackToOrgTotalsWhenComputeCacheFailed() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage
    viewModel.selectedApplicationID = "app-1"
    viewModel.setApplicationComputeCacheForTesting(applicationID: "app-1", state: .failed)

    let groups = Dictionary(uniqueKeysWithValues: viewModel.clusterGroups.map { ($0.0, $0.1.map(\.title)) })
    #expect(groups[.appClusters] == ["web"])
    #expect(groups[.managedQueues] == ["emails"])
}

@MainActor
@Test func viewModelFallsBackToOrgTotalsWhenComputeCacheLoadedEmpty() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage
    viewModel.selectedApplicationID = "app-1"
    viewModel.setApplicationComputeCacheForTesting(applicationID: "app-1", state: .loaded([]))

    let groups = Dictionary(uniqueKeysWithValues: viewModel.clusterGroups.map { ($0.0, $0.1.map(\.title)) })
    #expect(groups[.appClusters] == ["web"])
    #expect(groups[.managedQueues] == ["emails"])
}

private struct FixedExchangeRateClient: ExchangeRateProviding, Sendable {
    let rate: Double

    nonisolated func fetchRate(from source: String, to target: String) async throws -> Double {
        if source == target {
            return 1
        }

        return rate
    }
}

private struct FailingExchangeRateClient: ExchangeRateProviding, Sendable {
    nonisolated func fetchRate(from source: String, to target: String) async throws -> Double {
        throw URLError(.cannotConnectToHost)
    }
}

final class FakeTokenStore: TokenStoring, @unchecked Sendable {
    var storedToken: String?

    init(token: String? = nil) {
        storedToken = token
    }

    func readToken() throws -> String? { storedToken }
    func saveToken(_ token: String) throws { storedToken = token }
    func deleteToken() throws { storedToken = nil }
}

final class MockLaravelCloudClient: LaravelCloudProviding, @unchecked Sendable {
    var usageResult: Result<UsageResponse, Error> = .failure(URLError(.badServerResponse))
    var applicationsResult: Result<[CloudApplication], Error> = .success([])
    var environmentsResult: Result<[CloudEnvironment], Error> = .success([])

    func fetchUsage(token: String, environment: String?) async throws -> UsageResponse {
        try usageResult.get()
    }

    func fetchApplications(token: String) async throws -> [CloudApplication] {
        try applicationsResult.get()
    }

    func fetchEnvironments(token: String, applicationID: String) async throws -> [CloudEnvironment] {
        try environmentsResult.get()
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseByURL: [String: (Int, Data)] = [:]
    static let responseLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestURL = request.url?.absoluteString else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        Self.responseLock.lock()
        let registeredResponse = Self.responseByURL[requestURL]
        Self.responseLock.unlock()

        guard let registeredResponse else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: registeredResponse.0,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: registeredResponse.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func mocked(statusCode: Int, body: Data, url: URL) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.responseLock.lock()
        MockURLProtocol.responseByURL[url.absoluteString] = (statusCode, body)
        MockURLProtocol.responseLock.unlock()
        return URLSession(configuration: configuration)
    }
}

@MainActor
@Test func viewModelUsesCatalogNameForApplicationIDOptions() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageWithApplicationIDTitleFixture)
    let applications = try JSONDecoder.laravelCloud.decode(ApplicationsResponse.self, from: flatApplicationsFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage
    viewModel.applications = applications.data

    #expect(viewModel.applicationOptions == [ApplicationOption(id: "app-a1ebe3d4-70a6-4a6e-992a-25f6aa6716e9", name: "Ashbound Server")])

    viewModel.selectedApplicationID = "app-a1ebe3d4-70a6-4a6e-992a-25f6aa6716e9"
    #expect(viewModel.displayedApplicationName == "Ashbound Server")
}

@MainActor
@Test func viewModelInfersDeletedApplicationNameFromResources() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageWithDeletedApplicationFixture)
    let applications = try JSONDecoder.laravelCloud.decode(ApplicationsResponse.self, from: ashboundCatalogFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage
    viewModel.applications = applications.data

    let options = Set(viewModel.applicationOptions)
    #expect(options == [
        ApplicationOption(id: "app-a1ebe3d4-70a6-4a6e-992a-25f6aa6716e9", name: "sitepulse (deleted)"),
        ApplicationOption(id: "app-a1ef907f-ea38-4a95-a2a3-e968e769fd49", name: "ashbound-server"),
    ])
}

@MainActor
@Test func viewModelIncludesCatalogApplicationsWithoutUsageTotals() throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageWithDeletedApplicationFixture)
    let applications = try JSONDecoder.laravelCloud.decode(ApplicationsResponse.self, from: fullCatalogFixture)
    let viewModel = UsageViewModel(client: LaravelCloudClient())
    viewModel.usage = usage
    viewModel.applications = applications.data

    let optionIDs = Set(viewModel.applicationOptions.map(\.id))
    #expect(optionIDs.contains("app-a1ef907f-ea38-4a95-a2a3-e968e769fd49"))
    #expect(optionIDs.contains("app-a1fb732d-e469-45e4-85e6-bc215fd5a2f8"))
    #expect(optionIDs.contains("app-a1ebe3d4-70a6-4a6e-992a-25f6aa6716e9"))
}

private extension JSONDecoder {
    static var laravelCloud: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private let usageFixture = Data(
    """
    {
      "data": {
        "summary": {
          "current_spend_cents": 1234,
          "bandwidth": {
            "cost_cents": 50,
            "usage_percentage": 10,
            "allowance_bytes": 1048576
          },
          "credits": {
            "used_cents": 100,
            "total_cents": 500
          },
          "alert": null
        },
        "resources": {
          "total_cost_cents": 450,
          "databases": [
            {
              "id": "db-1",
              "name": "sitepulse_primary",
              "display_name": "Primary database",
              "type": "mysql",
              "total_cost_cents": 200
            },
            {
              "id": "db-2",
              "name": "other",
              "display_name": "Other database",
              "application_id": "app-2",
              "type": "mysql",
              "total_cost_cents": 999
            }
          ],
          "caches": [
            {
              "id": "cache-1",
              "name": "sitepulse_redis",
              "display_name": "redis",
              "type": "valkey",
              "total_cost_cents": 100
            },
            {
              "id": "cache-2",
              "name": "other-redis",
              "application_id": "app-2",
              "type": "valkey",
              "total_cost_cents": 999
            }
          ],
          "buckets": [
            {
              "id": "bucket-1",
              "name": "sitepulse_assets",
              "display_name": "assets",
              "storage_usage": "2 GB",
              "total_cost_cents": 75
            },
            {
              "id": "bucket-2",
              "name": "other-assets",
              "application_id": "app-2",
              "storage_usage": "4 GB",
              "total_cost_cents": 999
            }
          ],
          "websockets": [
            {
              "id": "ws-1",
              "name": "sitepulse",
              "display_name": "realtime",
              "usage_hours": "12 hours",
              "total_cost_cents": 75
            },
            {
              "id": "ws-2",
              "name": "other-realtime",
              "application_id": "app-2",
              "usage_hours": "50 hours",
              "total_cost_cents": 999
            }
          ]
        },
        "addons": {
          "total_cost_cents": 300,
          "items": [
            {
              "id": "addon-1",
              "name": "Insights",
              "application_id": "app-1",
              "total_cents": 125
            },
            {
              "id": "addon-2",
              "name": "Other add-on",
              "application_id": "app-2",
              "total_cents": 175
            }
          ]
        },
        "application_totals": {
          "total_cost_cents": 700,
          "application_count": 1,
          "applications": [
            {
              "id": "app-1",
              "name": "sitepulse",
              "application": {
                "name": "Site Pulse"
              },
              "vanity_domain": "sitepulse.test",
              "repository_url": "https://github.com/acme/sitepulse",
              "total_cost_cents": 700,
              "app_clusters": {
                "total_cost_cents": 500,
                "items": [
                  {
                    "id": "cluster-1",
                    "application_id": "app-1",
                    "name": "web",
                    "total_cost_cents": 500
                  }
                ]
              },
              "managed_queues": {
                "total_cost_cents": 200,
                "items": [
                  {
                    "id": "queue-1",
                    "application_id": "app-1",
                    "name": "emails",
                    "total_cost_cents": 200
                  }
                ]
              }
            }
          ]
        },
        "environment_usage": null
      },
      "meta": {
        "currency": "GBP",
        "period": 0,
        "available_periods": [
          {
            "from": "2026-06-01T00:00:00Z",
            "to": "2026-06-30T23:59:59Z"
          }
        ],
        "last_updated_at": "2026-06-13T20:30:00Z"
      }
    }
    """.utf8
)

private let usageWithApplicationIDTitleFixture = Data(
    """
    {
      "data": {
        "summary": {
          "current_spend_cents": 1234,
          "bandwidth": null,
          "credits": null,
          "alert": null
        },
        "resources": null,
        "addons": null,
        "application_totals": {
          "total_cost_cents": 700,
          "application_count": 1,
          "applications": [
            {
              "id": "app-a1ebe3d4-70a6-4a6e-992a-25f6aa6716e9",
              "name": "app-a1ebe3d4-70a6-4a6e-992a-25f6aa6716e9",
              "total_cost_cents": 700
            }
          ]
        },
        "environment_usage": null
      },
      "meta": {
        "currency": "GBP",
        "period": 0,
        "available_periods": [],
        "last_updated_at": "2026-06-13T20:30:00Z"
      }
    }
    """.utf8
)

private let environmentUsageFixture = Data(
    """
    {
      "data": {
        "summary": {
          "current_spend_cents": 329,
          "bandwidth": null,
          "credits": null,
          "alert": null
        },
        "resources": {
          "total_cost_cents": 0,
          "databases": [],
          "caches": [],
          "buckets": [],
          "websockets": []
        },
        "addons": {
          "total_cost_cents": 0,
          "items": []
        },
        "application_totals": {
          "total_cost_cents": 329,
          "application_count": 1,
          "applications": [
            {
              "identifier": "app-1",
              "environment_count": 1,
              "deleted": false,
              "total_cost_cents": 329
            }
          ]
        },
        "environment_usage": {
          "items": [
            {
              "identifier": "inst-1",
              "type": "app",
              "compute_profile": "Flex 1 vCPU",
              "compute_description": "1 GiB",
              "cpu_hours": 155.7,
              "active_replicas": 1,
              "total_replicas": 2,
              "total_cents": 322
            }
          ],
          "managed_queues": {
            "has_compute": true,
            "has_operations": true,
            "queues": [
              {
                "name": "",
                "compute_hours": 2.3,
                "operations_millions": 0.1,
                "compute_cost_cents": 2,
                "operations_cost_cents": 5,
                "total_cost_cents": 7
              }
            ],
            "total_cost_cents": 7
          },
          "total_cost_cents": 329
        }
      },
      "meta": {
        "currency": "GBP",
        "period": 0,
        "available_periods": [],
        "last_updated_at": "2026-06-13T20:30:00Z"
      }
    }
    """.utf8
)

private let applicationsFixture = Data(
    """
    {
      "data": [
        {
          "id": "app-1",
          "type": "applications",
          "attributes": {
            "name": "Site Pulse",
            "slug": "site-pulse",
            "repository": {
              "full_name": "acme/sitepulse"
            }
          }
        }
      ]
    }
    """.utf8
)

private let orgUsageWithEnvironmentUsageFixture = Data(
    """
    {
      "data": {
        "summary": {
          "current_spend_cents": 1234,
          "bandwidth": null,
          "credits": null,
          "alert": null
        },
        "resources": null,
        "addons": null,
        "application_totals": {
          "total_cost_cents": 700,
          "application_count": 1,
          "applications": [
            {
              "id": "app-1",
              "name": "sitepulse",
              "total_cost_cents": 700,
              "app_clusters": {
                "total_cost_cents": 500,
                "items": [
                  {
                    "id": "cluster-1",
                    "name": "web",
                    "total_cost_cents": 500
                  }
                ]
              },
              "managed_queues": {
                "total_cost_cents": 200,
                "items": [
                  {
                    "id": "queue-1",
                    "name": "emails",
                    "total_cost_cents": 200
                  }
                ]
              }
            }
          ]
        },
        "environment_usage": {
          "items": [
            {
              "identifier": "inst-1",
              "type": "app",
              "total_cents": 999
            }
          ],
          "total_cost_cents": 999
        }
      },
      "meta": {
        "currency": "GBP",
        "period": 0,
        "available_periods": [],
        "last_updated_at": "2026-06-13T20:30:00Z"
      }
    }
    """.utf8
)

private let flatApplicationsFixture = Data(
    """
    {
      "data": [
        {
          "id": "app-a1ebe3d4-70a6-4a6e-992a-25f6aa6716e9",
          "name": "Ashbound Server",
          "slug": "ashbound-server",
          "repository": "captenmasin/ashbound-server"
        }
      ]
    }
    """.utf8
)

private let ashboundCatalogFixture = Data(
    """
    {
      "data": [
        {
          "id": "app-a1ef907f-ea38-4a95-a2a3-e968e769fd49",
          "type": "applications",
          "attributes": {
            "name": "ashbound-server",
            "slug": "ashbound-server",
            "repository": {
              "full_name": "captenmasin/ashbound-server"
            }
          }
        }
      ]
    }
    """.utf8
)

private let fullCatalogFixture = Data(
    """
    {
      "data": [
        {
          "id": "app-a1ef907f-ea38-4a95-a2a3-e968e769fd49",
          "type": "applications",
          "attributes": {
            "name": "ashbound-server",
            "slug": "ashbound-server"
          }
        },
        {
          "id": "app-a1fb732d-e469-45e4-85e6-bc215fd5a2f8",
          "type": "applications",
          "attributes": {
            "name": "bookbound",
            "slug": "bookbound"
          }
        }
      ]
    }
    """.utf8
)

private let usageWithDeletedApplicationFixture = Data(
    """
    {
      "data": {
        "summary": {
          "current_spend_cents": 117,
          "bandwidth": null,
          "credits": null,
          "alert": null
        },
        "resources": {
          "total_cost_cents": 0,
          "databases": [
            {
              "name": "sitepulse_dev",
              "identifier": "royal-mode-62594335",
              "total_cents": 0,
              "deleted": false
            },
            {
              "name": "ashbound_server",
              "identifier": "delicate-mode-60347247",
              "total_cents": 0,
              "deleted": false
            }
          ],
          "caches": [],
          "buckets": [],
          "websockets": [
            {
              "name": "sitepulse",
              "identifier": "ws-a1ebf7ad-5146-463c-b604-d5c59a9cacfe",
              "total_cents": 0,
              "deleted": false
            }
          ]
        },
        "addons": null,
        "application_totals": {
          "total_cost_cents": 117,
          "application_count": 1,
          "applications": [
            {
              "identifier": "app-a1ebe3d4-70a6-4a6e-992a-25f6aa6716e9",
              "total_cost_cents": 117,
              "environment_count": 1,
              "deleted": true
            }
          ]
        },
        "environment_usage": null
      },
      "meta": {
        "currency": "USD",
        "period": 0,
        "available_periods": [],
        "last_updated_at": "2026-06-15T09:35:00+00:00"
      }
    }
    """.utf8
)
