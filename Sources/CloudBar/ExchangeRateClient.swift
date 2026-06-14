import Foundation

protocol ExchangeRateProviding: Sendable {
    func fetchRate(from source: String, to target: String) async throws -> Double
}

struct ExchangeRateClient: ExchangeRateProviding, Sendable {
    nonisolated func fetchRate(from source: String, to target: String) async throws -> Double {
        if source == target {
            return 1
        }

        var components = URLComponents(string: "https://api.frankfurter.app/latest")
        components?.queryItems = [
            URLQueryItem(name: "from", value: source),
            URLQueryItem(name: "to", value: target),
        ]

        guard let url = components?.url else {
            throw ExchangeRateError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ExchangeRateError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
        guard let rate = decoded.rates[target] else {
            throw ExchangeRateError.missingRate
        }

        return rate
    }
}

private struct FrankfurterResponse: Decodable {
    let rates: [String: Double]
}

enum ExchangeRateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingRate

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The exchange rate URL could not be created."
        case .invalidResponse:
            return "The exchange rate service returned an invalid response."
        case .missingRate:
            return "The exchange rate service did not return a rate for the selected currency."
        }
    }
}

enum SupportedCurrency: String, CaseIterable, Identifiable {
    case USD
    case EUR
    case GBP
    case CAD
    case AUD
    case NZD
    case JPY
    case CHF
    case SEK
    case NOK
    case DKK

    var id: String { rawValue }

    var title: String {
        Locale.current.localizedString(forCurrencyCode: rawValue) ?? rawValue
    }
}
