import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var period = 0
    @Published var environment = ""
    @Published private(set) var hasToken = false
    @Published private(set) var maskedToken = ""

    private let client: LaravelCloudClient
    private let keychain = TokenStore()
    private let currencyFormatter = NumberFormatter()

    init(client: LaravelCloudClient) {
        self.client = client
        currencyFormatter.numberStyle = .currency
        currencyFormatter.maximumFractionDigits = 2
    }

    var menuBarTitle: String {
        guard let usage else {
            return "Cloud"
        }

        return money(usage.data.summary.currentSpendCents)
    }

    var menuBarIcon: String {
        errorMessage == nil ? "cloud.fill" : "exclamationmark.icloud.fill"
    }

    var statusText: String {
        if isLoading {
            return "Refreshing usage..."
        }

        if let lastUpdated = usage?.meta.lastUpdatedAt, !lastUpdated.isEmpty {
            return "Updated \(lastUpdated)"
        }

        if errorMessage != nil {
            return "Check your token or connection"
        }

        return hasToken ? "Ready" : "Token required"
    }

    var applicationCountText: String? {
        guard let count = usage?.data.applicationTotals?.applicationCount else {
            return nil
        }

        return "\(count) application\(count == 1 ? "" : "s")"
    }

    var alertText: String? {
        guard let alert = usage?.data.summary.alert else {
            return nil
        }

        var parts: [String] = []
        if let threshold = alert.thresholdCents {
            parts.append("Alert at \(money(threshold))")
        }
        if let remaining = alert.remainingPercentage {
            parts.append("\(percent(remaining)) remaining")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    func loadSavedToken() async {
        do {
            let token = try keychain.readToken()
            hasToken = token != nil
            maskedToken = mask(token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveToken(_ token: String) async {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }

        do {
            try keychain.saveToken(cleaned)
            hasToken = true
            maskedToken = mask(cleaned)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearToken() async {
        do {
            try keychain.deleteToken()
            hasToken = false
            maskedToken = ""
            usage = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !isLoading else {
            return
        }

        do {
            guard let token = try keychain.readToken(), !token.isEmpty else {
                hasToken = false
                return
            }

            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            let response = try await client.fetchUsage(
                token: token,
                period: period,
                environment: environment.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
            usage = response
            hasToken = true
            maskedToken = mask(token)
            if let currency = response.meta.currency, !currency.isEmpty {
                currencyFormatter.currencyCode = currency
            }
        } catch {
            usage = nil
            errorMessage = error.localizedDescription
        }
    }

    func money(_ cents: Int?) -> String {
        guard let cents else {
            return "--"
        }

        let amount = Decimal(cents) / 100
        return currencyFormatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    func percent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return "\(Int(value.rounded()))%"
    }

    private func mask(_ token: String?) -> String {
        guard let token, !token.isEmpty else {
            return ""
        }

        if token.count <= 8 {
            return String(repeating: "*", count: token.count)
        }

        return "\(token.prefix(4))...\(token.suffix(4))"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
