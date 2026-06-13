import Foundation

struct LaravelCloudClient {
    private let baseURL = URL(string: "https://cloud.laravel.com/api/usage")!
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func fetchUsage(token: String, period: Int, environment: String?) async throws -> UsageResponse {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "period", value: String(period))]
        if let environment {
            queryItems.append(URLQueryItem(name: "environment", value: environment))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw LaravelCloudError.invalidURL
        }

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

        return try decoder.decode(UsageResponse.self, from: data)
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
}

struct AddonUsage: Decodable {
    let totalCostCents: Int?
    let items: [AddonItem]?
}

struct AddonItem: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let totalCents: Int?
}

struct ApplicationTotals: Decodable {
    let totalCostCents: Int?
    let applicationCount: Int?
}

struct TotalOnlyUsage: Decodable {
    let totalCostCents: Int?
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
