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
@Test func moneyConvertsCentsToDisplayCurrency() async throws {
    let usage = try JSONDecoder.laravelCloud.decode(UsageResponse.self, from: usageFixture)
    let viewModel = UsageViewModel(
        client: LaravelCloudClient(),
        exchangeRateClient: FixedExchangeRateClient(rate: 2)
    )
    viewModel.usage = usage
    await viewModel.setDisplayCurrency("USD")

    #expect(viewModel.convertedCentsToDisplayCurrency(100) == 200)
    #expect(viewModel.convertedCentsToDisplayCurrency(1234) == 2468)
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
