import AppKit
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var environment = ""
    @Published var selectedApplicationID = ""
    @Published private(set) var selectedCurrency = Locale.current.currency?.identifier ?? "USD" {
        didSet {
            currencyFormatter.currencyCode = selectedCurrency
        }
    }
    @Published var applications: [CloudApplication] = []
    @Published private(set) var hasToken = false
    @Published private(set) var maskedToken = ""
    @Published private(set) var isLoadingApplicationCompute = false
    @Published private var applicationComputeItemsByApplicationID: [String: [UsageLineItem]] = [:]

    private let client: LaravelCloudClient
    private let keychain = TokenStore()
    private let currencyFormatter = NumberFormatter()
    private let isoDateFormatter = ISO8601DateFormatter()
    private let displayDateFormatter = DateFormatter()

    init(client: LaravelCloudClient) {
        self.client = client
        currencyFormatter.numberStyle = .currency
        currencyFormatter.maximumFractionDigits = 2
        currencyFormatter.currencyCode = selectedCurrency
        displayDateFormatter.dateStyle = .medium
        displayDateFormatter.timeStyle = .short
    }

    var menuBarTitle: String {
        guard usage != nil else {
            return "Cloud"
        }

        return money(displayedCurrentSpendCents)
    }

    var menuBarIcon: String {
        errorMessage == nil ? "cloud.fill" : "exclamationmark.icloud.fill"
    }

    var statusText: String {
        if isLoading {
            return "Refreshing usage..."
        }

        if let lastUpdated = formattedUpdatedAt {
            return "Updated \(lastUpdated)"
        }

        if errorMessage != nil {
            return "Check your token or connection"
        }

        return hasToken ? "Ready" : "Token required"
    }

    var applicationCountText: String? {
        if !selectedApplicationID.isEmpty {
            return displayedApplicationName
        }

        guard let count = usage?.data.applicationTotals?.applicationCount else {
            return nil
        }

        return "\(count) application\(count == 1 ? "" : "s")"
    }

    var applicationOptions: [ApplicationOption] {
        let applications = usage?.data.applicationTotals?.applications ?? []
        let options = applications.map { item in
            ApplicationOption(
                id: item.applicationID ?? item.id,
                name: applicationName(for: item)
            )
        }

        return Array(Set(options)).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var displayedApplicationName: String {
        guard !selectedApplicationID.isEmpty else {
            return "All applications"
        }

        return applicationOptions.first { $0.id == selectedApplicationID }?.name ?? "Selected application"
    }

    var selectedApplication: UsageLineItem? {
        guard !selectedApplicationID.isEmpty else {
            return nil
        }

        return usage?.data.applicationTotals?.applications.first { item in
            item.applicationID == selectedApplicationID || item.id == selectedApplicationID
        }
    }

    var selectedApplicationCatalogItem: CloudApplication? {
        guard !selectedApplicationID.isEmpty else {
            return nil
        }

        if let selectedApplication {
            return catalogApplication(for: selectedApplication)
        }

        return applications.first { $0.matchesApplication(id: selectedApplicationID, terms: []) }
    }

    var selectedDeployURL: URL? {
        selectedApplication?.deployURL ?? selectedApplicationCatalogItem?.deployURL
    }

    var selectedVisitURL: URL? {
        selectedApplication?.visitURL
    }

    var selectedRepositoryURL: URL? {
        selectedApplication?.repositoryURL ?? selectedApplicationCatalogItem?.repositoryURL
    }

    var billingPeriodText: String? {
        guard let usage else {
            return nil
        }

        guard let period = usage.meta.period,
              let availablePeriods = usage.meta.availablePeriods,
              availablePeriods.indices.contains(period) else {
            return "Current billing period"
        }

        let selectedPeriod = availablePeriods[period]
        let from = displayDate(selectedPeriod.from)
        let to = displayDate(selectedPeriod.to)

        switch (from, to) {
        case let (from?, to?):
            return "Billing period \(from) - \(to)"
        case let (from?, nil):
            return "Billing period from \(from)"
        case let (nil, to?):
            return "Billing period through \(to)"
        case (nil, nil):
            return period == 0 ? "Current billing period" : "Billing period \(period)"
        }
    }

    var displayedCurrentSpendCents: Int? {
        guard !selectedApplicationID.isEmpty else {
            return usage?.data.summary.currentSpendCents
        }

        let visibleTotals = [
            displayedApplicationTotalCents,
            displayedResourcesTotalCents,
            displayedAddonsTotalCents,
            displayedBandwidth?.costCents
        ].compactMap { $0 }

        guard !visibleTotals.isEmpty else {
            return nil
        }

        return visibleTotals.reduce(0, +)
    }

    var displayedBandwidth: BandwidthUsage? {
        guard selectedApplicationID.isEmpty else {
            return nil
        }

        return usage?.data.summary.bandwidth
    }

    var displayedApplicationTotalCents: Int? {
        guard !selectedApplicationID.isEmpty else {
            return usage?.data.applicationTotals?.totalCostCents
        }

        return selectedApplication?.totalCostCents
    }

    var filteredApplicationItems: [UsageLineItem] {
        if !selectedApplicationID.isEmpty,
           let scopedComputeItems = applicationComputeItemsByApplicationID[selectedApplicationID] {
            return scopedComputeItems.flatMap(\.flattened)
        }

        let environmentItems = usage?.data.environmentUsage?.items ?? []
        let applicationItems = usage?.data.applicationTotals?.applications ?? []
        let items = environmentItems.isEmpty ? applicationItems : environmentItems

        guard !selectedApplicationID.isEmpty else {
            return items.flatMap(\.flattened)
        }

        return items.filter { item in
            item.matchesApplication(id: selectedApplicationID, terms: selectedApplicationSearchTerms)
        }.flatMap(\.flattened)
    }

    var clusterGroups: [(UsageClusterType, [UsageLineItem])] {
        UsageClusterType.allCases.map { type in
            (type, filteredApplicationItems.filter { $0.clusterType == type })
        }
    }

    var displayedResourcesTotalCents: Int? {
        guard !selectedApplicationID.isEmpty else {
            return usage?.data.resources?.totalCostCents
        }

        let totals = displayedDatabaseItems
            + displayedCacheItems
            + displayedBucketItems
            + displayedWebSocketItems

        let costValues = totals.compactMap(\.totalCostCents)
        guard !costValues.isEmpty else {
            return nil
        }

        return costValues.reduce(0, +)
    }

    var displayedDatabaseItems: [UsageLineItem] {
        filteredResourceItems(usage?.data.resources?.databases ?? [])
    }

    var displayedCacheItems: [UsageLineItem] {
        filteredResourceItems(usage?.data.resources?.caches ?? [])
    }

    var displayedBucketItems: [UsageLineItem] {
        filteredResourceItems(usage?.data.resources?.buckets ?? [])
    }

    var displayedWebSocketItems: [UsageLineItem] {
        filteredResourceItems(usage?.data.resources?.websockets ?? [])
    }

    var displayedAddonItems: [AddonItem] {
        let items = usage?.data.addons?.items ?? []
        guard !selectedApplicationID.isEmpty else {
            return items
        }

        return items.filter { item in
            item.matchesApplication(id: selectedApplicationID, terms: selectedApplicationSearchTerms)
        }
    }

    var displayedAddonsTotalCents: Int? {
        guard !selectedApplicationID.isEmpty else {
            return usage?.data.addons?.totalCostCents
        }

        let totals = displayedAddonItems.compactMap(\.totalCents)
        guard !totals.isEmpty else {
            return nil
        }

        return totals.reduce(0, +)
    }

    var formattedUpdatedAt: String? {
        guard let rawDate = usage?.meta.lastUpdatedAt, !rawDate.isEmpty else {
            return nil
        }

        if let date = isoDateFormatter.date(from: rawDate) ?? Self.fallbackDateFormatter.date(from: rawDate) {
            return displayDateFormatter.string(from: date)
        }

        return rawDate
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
                environment: environment.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
            usage = response
            applications = (try? await client.fetchApplications(token: token)) ?? []
            applicationComputeItemsByApplicationID = [:]
            hasToken = true
            maskedToken = mask(token)
            if let currency = response.meta.currency, !currency.isEmpty {
                selectedCurrency = currency
            }

            if !selectedApplicationID.isEmpty && !applicationOptions.contains(where: { $0.id == selectedApplicationID }) {
                selectedApplicationID = ""
            }

            await loadSelectedApplicationCompute(token: token)
        } catch {
            usage = nil
            errorMessage = error.localizedDescription
        }
    }

    func loadSelectedApplicationCompute() async {
        do {
            guard let token = try keychain.readToken(), !token.isEmpty else {
                return
            }

            await loadSelectedApplicationCompute(token: token)
        } catch {
            return
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

    func open(_ url: URL?) {
        guard let url else {
            return
        }

        NSWorkspace.shared.open(url)
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

    private func applicationName(for item: UsageLineItem) -> String {
        if let application = catalogApplication(for: item) {
            return application.name
        }

        if let applicationName = item.applicationName, !applicationName.looksLikeApplicationID {
            return applicationName
        }

        if !item.title.looksLikeApplicationID {
            return item.title
        }

        return item.applicationID ?? item.id
    }

    private func catalogApplication(for item: UsageLineItem) -> CloudApplication? {
        let id = item.applicationID ?? item.id
        let terms = ([item.title, item.subtitle, item.applicationName] + item.searchTerms).compactMap { $0 }

        return applications.first { application in
            application.matchesApplication(id: id, terms: terms)
        }
    }

    private func filteredResourceItems(_ items: [UsageLineItem]) -> [UsageLineItem] {
        guard !selectedApplicationID.isEmpty else {
            return items
        }

        return items.filter { item in
            item.matchesApplication(id: selectedApplicationID, terms: selectedApplicationSearchTerms)
        }
    }

    private func loadSelectedApplicationCompute(token: String) async {
        let applicationID = selectedApplicationID
        guard !applicationID.isEmpty,
              applicationComputeItemsByApplicationID[applicationID] == nil,
              !isLoadingApplicationCompute else {
            return
        }

        isLoadingApplicationCompute = true
        defer { isLoadingApplicationCompute = false }

        do {
            let environments = try await client.fetchEnvironments(token: token, applicationID: applicationID)
            var responses: [UsageResponse] = []

            for environment in environments {
                let response = try await client.fetchUsage(token: token, environment: environment.id)
                responses.append(response)
            }

            applicationComputeItemsByApplicationID[applicationID] = responses.flatMap { response in
                response.data.environmentUsage?.computeItems ?? []
            }
        } catch {
            applicationComputeItemsByApplicationID[applicationID] = []
        }
    }

    private var selectedApplicationSearchTerms: [String] {
        let terms: [String?] = [
            selectedApplicationID,
            displayedApplicationName,
            selectedApplication?.title,
            selectedApplication?.applicationName,
            selectedApplicationCatalogItem?.name,
            selectedApplicationCatalogItem?.slug
        ]

        return (terms.compactMap { $0 } + (selectedApplicationCatalogItem?.searchTerms ?? []))
            .compactMap { value in
            guard !value.isEmpty, !value.looksLikeApplicationID else {
                return nil
            }

            return value
        }
    }

    private func displayDate(_ rawDate: String?) -> String? {
        guard let rawDate, !rawDate.isEmpty else {
            return nil
        }

        if let date = isoDateFormatter.date(from: rawDate) ?? Self.fallbackDateFormatter.date(from: rawDate) {
            return displayDateFormatter.string(from: date)
        }

        return rawDate
    }

    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

struct ApplicationOption: Identifiable, Hashable {
    let id: String
    let name: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var looksLikeApplicationID: Bool {
        hasPrefix("app-")
    }

    var normalizedApplicationKey: String {
        String(lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

private extension CloudApplication {
    func matchesApplication(id: String, terms: [String]) -> Bool {
        if self.id == id {
            return true
        }

        let normalizedTerms = ([id] + terms)
            .map(\.normalizedApplicationKey)
            .filter { !$0.isEmpty }
        let searchableValues = searchTerms
            .map(\.normalizedApplicationKey)
            .filter { !$0.isEmpty }

        return searchableValues.contains { value in
            normalizedTerms.contains { term in
                value == term || value.hasPrefix(term) || term.hasPrefix(value)
            }
        }
    }
}
