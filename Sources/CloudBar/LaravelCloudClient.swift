import Foundation

struct LaravelCloudClient {
    private let apiBaseURL = URL(string: "https://cloud.laravel.com/api")!
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func fetchUsage(token: String, environment: String?) async throws -> UsageResponse {
        var components = URLComponents(url: apiBaseURL.appending(path: "usage"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if let environment {
            queryItems.append(URLQueryItem(name: "environment", value: environment))
        }
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw LaravelCloudError.invalidURL
        }

        return try await fetch(url: url, token: token)
    }

    func fetchApplications(token: String) async throws -> [CloudApplication] {
        let response: ApplicationsResponse = try await fetch(
            url: apiBaseURL.appending(path: "applications"),
            token: token
        )
        return response.data
    }

    func fetchEnvironments(token: String, applicationID: String) async throws -> [CloudEnvironment] {
        let response: EnvironmentsResponse = try await fetch(
            url: apiBaseURL
                .appending(path: "applications")
                .appending(path: applicationID)
                .appending(path: "environments"),
            token: token
        )
        return response.data
    }

    private func fetch<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LaravelCloudError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = try? decoder.decode(APIErrorResponse.self, from: data)
            throw LaravelCloudError.api(statusCode: httpResponse.statusCode, message: message?.message)
        }

        return try decoder.decode(T.self, from: data)
    }
}

enum LaravelCloudError: LocalizedError {
    case invalidURL
    case invalidResponse
    case api(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Laravel Cloud usage URL could not be created."
        case .invalidResponse:
            return "Laravel Cloud returned an invalid response."
        case let .api(statusCode, message):
            if let message, !message.isEmpty {
                return "\(message) (\(statusCode))"
            }
            return "Laravel Cloud returned HTTP \(statusCode)."
        }
    }
}

struct APIErrorResponse: Decodable {
    let message: String?
}

struct UsageResponse: Decodable {
    let data: UsageData
    let meta: UsageMeta
}

struct ApplicationsResponse: Decodable {
    let data: [CloudApplication]
}

struct EnvironmentsResponse: Decodable {
    let data: [CloudEnvironment]
}

struct CloudEnvironment: Decodable, Identifiable, Hashable {
    let id: String
    let attributes: Attributes

    var name: String {
        attributes.name
    }

    var slug: String? {
        attributes.slug
    }

    struct Attributes: Decodable, Hashable {
        let name: String
        let slug: String?
    }
}

struct CloudApplication: Decodable, Identifiable, Hashable {
    let id: String
    let attributes: Attributes

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        if let attributes = try container.decodeIfPresent(Attributes.self, forKey: .attributes) {
            self.attributes = attributes
            return
        }

        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let displayNameSnakeCase = try container.decodeIfPresent(String.self, forKey: .displayNameSnakeCase)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let label = try container.decodeIfPresent(String.self, forKey: .label)
        let slugName = try container.decodeIfPresent(String.self, forKey: .slug)
        let name = decodedName ?? displayName ?? displayNameSnakeCase ?? title ?? label ?? slugName ?? id
        let slug = try container.decodeIfPresent(String.self, forKey: .slug)
        let repository = try container.decodeIfPresent(Repository.self, forKey: .repository)
            ?? container.decodeIfPresent(Repository.self, forKey: .repo)

        attributes = Attributes(name: name, slug: slug, repository: repository)
    }

    var name: String {
        attributes.name
    }

    var slug: String? {
        attributes.slug
    }

    var deployURL: URL? {
        URL(string: "https://cloud.laravel.com/applications/\(id)/deployments")
    }

    var repositoryURL: URL? {
        attributes.repository?.url
    }

    var searchTerms: [String] {
        let repositoryTerms = attributes.repository?.searchTerms ?? []
        return [id, name, slug].compactMap { $0 } + repositoryTerms
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case attributes
        case name
        case displayName
        case displayNameSnakeCase = "display_name"
        case title
        case label
        case slug
        case repository
        case repo
    }

    struct Attributes: Decodable, Hashable {
        let name: String
        let slug: String?
        let repository: Repository?
    }

    struct Repository: Decodable, Hashable {
        let fullName: String?
        let url: URL?

        init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(),
               let value = try? container.decode(String.self) {
                fullName = value.contains("/") ? value : nil
                url = URL.webURL(from: value) ?? fullName.flatMap { URL(string: "https://github.com/\($0)") }
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
            let url = try container.decodeIfPresent(URL.self, forKey: .url)
            let htmlURL = try container.decodeIfPresent(URL.self, forKey: .htmlUrl)
            self.url = url ?? htmlURL ?? fullName.flatMap { URL(string: "https://github.com/\($0)") }
        }

        private enum CodingKeys: String, CodingKey {
            case fullName
            case url
            case htmlUrl
        }

        var searchTerms: [String] {
            let urlTerms = [url?.host(), url?.lastPathComponent].compactMap { $0 }
            let repositoryParts = fullName?.split(separator: "/").map(String.init) ?? []
            return [fullName].compactMap { $0 } + urlTerms + repositoryParts
        }
    }
}

struct UsageData: Decodable {
    let summary: UsageSummary
    let resources: ResourceUsage?
    let addons: AddonUsage?
    let applicationTotals: ApplicationTotals?
    let environmentUsage: TotalOnlyUsage?
}

struct UsageSummary: Decodable {
    let currentSpendCents: Int?
    let bandwidth: BandwidthUsage?
    let credits: CreditUsage?
    let alert: AlertUsage?
}

struct BandwidthUsage: Decodable {
    let costCents: Int?
    let usagePercentage: Double?
    let allowanceBytes: Int64?
}

struct CreditUsage: Decodable {
    let usedCents: Int?
    let totalCents: Int?
}

struct AlertUsage: Decodable {
    let thresholdCents: Int?
    let remainingPercentage: Double?
}

struct ResourceUsage: Decodable {
    let totalCostCents: Int?
    let databases: [UsageLineItem]
    let caches: [UsageLineItem]
    let buckets: [UsageLineItem]
    let websockets: [UsageLineItem]

    private enum CodingKeys: String, CodingKey {
        case totalCostCents
        case databases
        case caches
        case buckets
        case websockets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCostCents = try container.decodeIfPresent(Int.self, forKey: .totalCostCents)
        databases = try container.decodeIfPresent([UsageLineItem].self, forKey: .databases) ?? []
        caches = try container.decodeIfPresent([UsageLineItem].self, forKey: .caches) ?? []
        buckets = try container.decodeIfPresent([UsageLineItem].self, forKey: .buckets) ?? []
        websockets = try container.decodeIfPresent([UsageLineItem].self, forKey: .websockets) ?? []
    }
}

struct AddonUsage: Decodable {
    let totalCostCents: Int?
    let items: [AddonItem]?
}

struct AddonItem: Decodable, Identifiable {
    let id: String
    let name: String
    let totalCents: Int?
    let applicationID: String?
    let applicationName: String?
    let searchTerms: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var fields: [String: UsageValue] = [:]

        for key in container.allKeys {
            fields[key.stringValue] = try container.decode(UsageValue.self, forKey: key)
        }

        id = fields.firstString(for: ["id", "identifier", "uuid", "name"]) ?? UUID().uuidString
        name = fields.firstString(for: ["displayName", "display_name", "title", "label", "name", "identifier"]) ?? id
        totalCents = fields.firstInt(for: ["totalCents", "total_cents", "totalCostCents", "total_cost_cents", "costCents", "cost_cents", "amountCents", "amount_cents"])
        applicationID = fields.firstString(for: ["applicationID", "applicationId", "application_id", "appID", "appId", "app_id"])
        applicationName = fields.firstString(for: ["applicationName", "application_name", "appName", "app_name", "applicationDisplayName", "application_display_name"])
            ?? fields.firstString(in: ["application", "app"], for: ["name", "displayName", "display_name", "title", "label"])
        searchTerms = fields.searchTerms
    }
}

struct ApplicationTotals: Decodable {
    let totalCostCents: Int?
    let applicationCount: Int?
    let applications: [UsageLineItem]

    private enum CodingKeys: String, CodingKey {
        case totalCostCents
        case applicationCount
        case applications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCostCents = try container.decodeIfPresent(Int.self, forKey: .totalCostCents)
        applicationCount = try container.decodeIfPresent(Int.self, forKey: .applicationCount)
        applications = try container.decodeIfPresent([UsageLineItem].self, forKey: .applications) ?? []
    }
}

struct TotalOnlyUsage: Decodable {
    let totalCostCents: Int?
    let items: [UsageLineItem]
    let managedQueues: ManagedQueueUsage?

    var computeItems: [UsageLineItem] {
        items + (managedQueues?.queues ?? [])
    }

    private enum CodingKeys: String, CodingKey {
        case totalCostCents
        case items
        case managedQueues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCostCents = try container.decodeIfPresent(Int.self, forKey: .totalCostCents)
        items = try container.decodeIfPresent([UsageLineItem].self, forKey: .items) ?? []
        managedQueues = try container.decodeIfPresent(ManagedQueueUsage.self, forKey: .managedQueues)
    }
}

struct ManagedQueueUsage: Decodable {
    let totalCostCents: Int?
    let queues: [UsageLineItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var fields: [String: UsageValue] = [:]

        for key in container.allKeys {
            fields[key.stringValue] = try container.decode(UsageValue.self, forKey: key)
        }

        totalCostCents = fields.firstInt(for: ["totalCostCents", "total_cost_cents"])
        queues = fields.lineItems(inheriting: .managedQueues)
    }
}

struct UsageMeta: Decodable {
    let currency: String?
    let period: Int?
    let availablePeriods: [UsagePeriod]?
    let lastUpdatedAt: String?
}

struct UsagePeriod: Decodable {
    let from: String?
    let to: String?
}

struct UsageLineItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let totalCostCents: Int?
    let applicationID: String?
    let applicationName: String?
    let clusterType: UsageClusterType?
    let deployURL: URL?
    let visitURL: URL?
    let repositoryURL: URL?
    let searchTerms: [String]
    let children: [UsageLineItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var fields: [String: UsageValue] = [:]

        for key in container.allKeys {
            fields[key.stringValue] = try container.decode(UsageValue.self, forKey: key)
        }

        self.init(fields: fields)
    }

    fileprivate init(fields: [String: UsageValue], inheritedClusterType: UsageClusterType? = nil) {
        let id = fields.firstString(for: ["id", "identifier", "uuid", "resource_id", "application_id", "environment_id", "name"]) ?? UUID().uuidString
        self.id = id
        title = fields.firstString(for: ["displayName", "display_name", "title", "label", "name", "identifier", "database", "databaseIdentifier", "database_identifier", "cache", "bucket", "websocket", "cluster", "environmentName", "environment_name", "applicationName", "application_name"]) ?? id
        subtitle = fields.subtitle(excluding: title)
        totalCostCents = fields.firstInt(for: ["totalCostCents", "total_cost_cents", "totalCents", "total_cents", "costCents", "cost_cents", "currentSpendCents", "current_spend_cents", "amountCents", "amount_cents"])
        applicationID = fields.firstString(for: ["applicationID", "applicationId", "application_id", "appID", "appId", "app_id"])
        applicationName = fields.firstString(for: ["applicationName", "application_name", "appName", "app_name", "applicationDisplayName", "application_display_name", "displayName", "display_name"])
            ?? fields.firstString(in: ["application", "app"], for: ["name", "displayName", "display_name", "title", "label"])
        clusterType = UsageClusterType(fields.firstString(for: ["cluster_type", "clusterType", "type", "instance_type", "instanceType", "category"])) ?? inheritedClusterType
        let applicationIdentifier = fields.firstString(for: ["applicationID", "applicationId", "application_id", "appID", "appId", "app_id", "id"]) ?? id
        deployURL = fields.firstURL(for: ["deployURL", "deployUrl", "deploy_url", "deploymentURL", "deploymentUrl", "deployment_url", "deploymentsURL", "deploymentsUrl", "deployments_url"])
            ?? URL(string: "https://cloud.laravel.com/applications/\(applicationIdentifier)/deployments")
        visitURL = fields.firstURL(for: ["visitURL", "visitUrl", "visit_url", "appURL", "appUrl", "app_url", "applicationURL", "applicationUrl", "application_url", "url", "vanityDomain", "vanity_domain", "domain", "primaryDomain", "primary_domain"])
        repositoryURL = fields.firstURL(for: ["repositoryURL", "repositoryUrl", "repository_url", "repoURL", "repoUrl", "repo_url", "sourceURL", "sourceUrl", "source_url", "repository", "repo"])
        searchTerms = fields.searchTerms
        children = fields.lineItems(inheriting: clusterType)
    }

    var flattened: [UsageLineItem] {
        [self] + children.flatMap(\.flattened)
    }

    func matchesApplication(id: String, terms: [String]) -> Bool {
        let normalizedTerms = terms.map(\.normalizedSearchKey).filter { !$0.isEmpty }
        let searchableValues = ([self.id, title, subtitle, applicationID, applicationName] + searchTerms)
            .compactMap { $0 }
            .map(\.normalizedSearchKey)

        return applicationID == id
            || self.id == id
            || searchableValues.contains(where: { value in
                normalizedTerms.contains { term in
                    value == term || value.hasPrefix(term) || value.contains(term)
                }
            })
            || children.contains { $0.matchesApplication(id: id, terms: terms) }
    }
}

enum UsageClusterType: String, CaseIterable {
    case appClusters
    case workerClusters
    case managedQueues

    init?(_ rawValue: String?) {
        guard let rawValue else {
            return nil
        }

        switch rawValue.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "app", "app_cluster", "app_clusters", "application", "general":
            self = .appClusters
        case "worker", "worker_cluster", "worker_clusters", "queue", "service":
            self = .workerClusters
        case "managed_queue", "managed_queues":
            self = .managedQueues
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .appClusters:
            return "App clusters"
        case .workerClusters:
            return "Worker clusters"
        case .managedQueues:
            return "Managed queues"
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum UsageValue: Decodable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: UsageValue])
    case array([UsageValue])
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: UsageValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(UsageValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [UsageValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(UsageValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

private extension Dictionary where Key == String, Value == UsageValue {
    func firstString(for keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue {
                return value
            }

            if let nestedValue = nestedValue(for: key)?.stringValue {
                return nestedValue
            }
        }

        return nil
    }

    func firstString(in parentKeys: [String], for childKeys: [String]) -> String? {
        for parentKey in parentKeys {
            if case let .object(object) = self[parentKey] {
                return object.firstString(for: childKeys)
            }
        }

        return nil
    }

    func firstURL(for keys: [String]) -> URL? {
        for key in keys {
            if let value = self[key]?.urlValue {
                return value
            }

            if let nestedValue = nestedValue(for: key)?.urlValue {
                return nestedValue
            }
        }

        return nil
    }

    func firstInt(for keys: [String]) -> Int? {
        for key in keys {
            if let value = self[key]?.intValue {
                return value
            }

            if let nestedValue = nestedValue(for: key)?.intValue {
                return nestedValue
            }
        }

        return nil
    }

    func subtitle(excluding title: String) -> String? {
        let values: [String?] = [
            firstString(for: ["type", "plan", "size", "region"]),
            firstString(for: ["environmentName", "environment_name", "environment", "slug"]),
            firstString(for: ["usage", "usageHours", "usage_hours", "storage", "storageUsage", "storage_usage", "requests"])
        ]
        let details: [String] = values.compactMap { value in
            guard let value, value != title else {
                return nil
            }

            return value
        }

        return details.isEmpty ? nil : details.joined(separator: " - ")
    }

    func lineItems(inheriting inheritedClusterType: UsageClusterType?) -> [UsageLineItem] {
        let keys: [(String, UsageClusterType?)] = [
            ("items", inheritedClusterType),
            ("data", inheritedClusterType),
            ("usage", inheritedClusterType),
            ("clusters", inheritedClusterType),
            ("environments", inheritedClusterType),
            ("instances", inheritedClusterType),
            ("queues", inheritedClusterType),
            ("general", .appClusters),
            ("appClusters", .appClusters),
            ("app_clusters", .appClusters),
            ("workerClusters", .workerClusters),
            ("worker_clusters", .workerClusters),
            ("managedQueue", .managedQueues),
            ("managed_queue", .managedQueues),
            ("managedQueues", .managedQueues),
            ("managed_queues", .managedQueues)
        ]
        var items: [UsageLineItem] = []
        var seenIDs: Set<String> = []

        for (key, clusterType) in keys {
            if case let .array(values) = self[key] {
                for item in values.flatMap({ $0.lineItems(inheriting: clusterType) }) where seenIDs.insert(item.dedupeKey).inserted {
                    items.append(item)
                }
            }

            if case let .object(object) = self[key] {
                for item in object.lineItems(inheriting: clusterType) where seenIDs.insert(item.dedupeKey).inserted {
                    items.append(item)
                }
            }
        }

        return items
    }

    var searchTerms: [String] {
        values.flatMap(\.searchTerms)
    }

    private func nestedValue(for key: String) -> UsageValue? {
        for value in values {
            if case let .object(object) = value {
                if let match = object[key] {
                    return match
                }

                if let match = object.nestedValue(for: key) {
                    return match
                }
            }
        }

        return nil
    }
}

private extension UsageValue {
    var stringValue: String? {
        switch self {
        case let .string(value):
            return value.isEmpty ? nil : value
        case let .int(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .bool(value):
            return value ? "Yes" : "No"
        case let .object(object):
            return object.firstString(for: ["name", "label", "identifier", "slug", "id"])
        case let .array(values):
            return values.first?.stringValue
        case .null:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case let .int(value):
            return value
        case let .double(value):
            return Int(value)
        case let .string(value):
            return Int(value)
        case let .object(object):
            return object.firstInt(for: ["totalCostCents", "total_cost_cents", "totalCents", "total_cents", "costCents", "cost_cents"])
        case .bool, .array, .null:
            return nil
        }
    }

    func lineItems(inheriting inheritedClusterType: UsageClusterType?) -> [UsageLineItem] {
        switch self {
        case let .object(object):
            let nestedItems = object.lineItems(inheriting: inheritedClusterType)
            if nestedItems.isEmpty {
                return [UsageLineItem(fields: object, inheritedClusterType: inheritedClusterType)]
            }

            return nestedItems
        case let .array(values):
            return values.flatMap { $0.lineItems(inheriting: inheritedClusterType) }
        case .string, .int, .double, .bool, .null:
            return []
        }
    }

    var urlValue: URL? {
        switch self {
        case let .string(value):
            return URL.webURL(from: value)
        case let .object(object):
            return object.firstURL(for: ["href", "url", "webURL", "webUrl", "web_url", "htmlURL", "htmlUrl", "html_url", "name", "domain"])
        case let .array(values):
            return values.compactMap(\.urlValue).first
        case .int, .double, .bool, .null:
            return nil
        }
    }

    var searchTerms: [String] {
        switch self {
        case let .string(value):
            return [value]
        case let .int(value):
            return [String(value)]
        case let .double(value):
            return [String(value)]
        case let .bool(value):
            return [String(value)]
        case let .object(object):
            return object.searchTerms
        case let .array(values):
            return values.flatMap(\.searchTerms)
        case .null:
            return []
        }
    }
}

private extension UsageLineItem {
    var dedupeKey: String {
        "\(id)-\(clusterType?.rawValue ?? "none")"
    }
}

extension AddonItem {
    func matchesApplication(id: String, terms: [String]) -> Bool {
        let normalizedTerms = terms.map(\.normalizedSearchKey).filter { !$0.isEmpty }
        let searchableValues = ([self.id, name, applicationID, applicationName] + searchTerms)
            .compactMap { $0 }
            .map(\.normalizedSearchKey)

        return applicationID == id
            || self.id == id
            || searchableValues.contains(where: { value in
                normalizedTerms.contains { term in
                    value == term || value.hasPrefix(term) || value.contains(term)
                }
            })
    }
}

private extension String {
    var normalizedSearchKey: String {
        String(lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

private extension URL {
    static func webURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        guard trimmed.contains(".") else {
            return nil
        }

        return URL(string: "https://\(trimmed)")
    }
}
