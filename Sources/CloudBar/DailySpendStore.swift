import Foundation

enum DailyCostCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case appClusters
    case workerClusters
    case managedQueues
    case databases
    case caches
    case buckets
    case webSockets
    case addons
    case bandwidth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appClusters:
            return "App clusters"
        case .workerClusters:
            return "Worker clusters"
        case .managedQueues:
            return "Managed queues"
        case .databases:
            return "Databases"
        case .caches:
            return "Caches"
        case .buckets:
            return "Buckets"
        case .webSockets:
            return "WebSockets"
        case .addons:
            return "Add-ons"
        case .bandwidth:
            return "Bandwidth"
        }
    }

    var sortOrder: Int {
        switch self {
        case .appClusters: 0
        case .workerClusters: 1
        case .managedQueues: 2
        case .databases: 3
        case .caches: 4
        case .buckets: 5
        case .webSockets: 6
        case .addons: 7
        case .bandwidth: 8
        }
    }
}

struct DailyCostCategorySegment: Identifiable, Hashable, Sendable {
    let category: DailyCostCategory
    let costCents: Int

    var id: String { category.rawValue }
}

struct DailyCostEntry: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    let costCents: Int
    let segments: [DailyCostCategorySegment]

    init(date: Date, costCents: Int, segments: [DailyCostCategorySegment] = []) {
        self.date = date
        self.costCents = costCents
        self.segments = segments
        id = Self.dayKey(for: date)
    }

    var hasSegmentedBreakdown: Bool {
        !segments.isEmpty
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct DailySpendStore {
    private struct StoredSnapshot: Codable, Hashable {
        let dayKey: String
        let cumulativeCents: Int
        var categoryCents: [String: Int]?
    }

    private struct StoredHistory: Codable {
        var snapshots: [StoredSnapshot]
    }

    private let defaults: UserDefaults
    private let storageKey = "dailySpendHistories"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func periodKey(period: Int?, periodFrom: String?) -> String {
        let periodValue = period.map(String.init) ?? "current"
        let from = periodFrom?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown"
        return "\(periodValue):\(from)"
    }

    func record(
        periodKey: String,
        scopeKey: String,
        cumulativeCents: Int,
        categoryCents: [DailyCostCategory: Int] = [:],
        on date: Date = .now,
        calendar: Calendar = .current
    ) {
        let dayKey = DailyCostEntry.dayKey(for: date, calendar: calendar)
        var histories = loadHistories()
        let historyKey = Self.historyKey(periodKey: periodKey, scopeKey: scopeKey)
        var history = histories[historyKey] ?? StoredHistory(snapshots: [])

        let encodedCategories = categoryCents.reduce(into: [String: Int]()) { result, entry in
            guard entry.value > 0 else {
                return
            }

            result[entry.key.rawValue] = entry.value
        }

        if let index = history.snapshots.firstIndex(where: { $0.dayKey == dayKey }) {
            let existing = history.snapshots[index]
            var mergedCategories = existing.categoryCents ?? [:]

            for (key, value) in encodedCategories {
                mergedCategories[key] = max(mergedCategories[key] ?? 0, value)
            }

            history.snapshots[index] = StoredSnapshot(
                dayKey: dayKey,
                cumulativeCents: max(existing.cumulativeCents, cumulativeCents),
                categoryCents: mergedCategories.isEmpty ? nil : mergedCategories
            )
        } else {
            history.snapshots.append(
                StoredSnapshot(
                    dayKey: dayKey,
                    cumulativeCents: cumulativeCents,
                    categoryCents: encodedCategories.isEmpty ? nil : encodedCategories
                )
            )
            history.snapshots.sort { $0.dayKey < $1.dayKey }
        }

        histories[historyKey] = history
        saveHistories(histories)
    }

    func dailyCosts(
        periodKey: String,
        scopeKey: String,
        calendar: Calendar = .current
    ) -> [DailyCostEntry] {
        let historyKey = Self.historyKey(periodKey: periodKey, scopeKey: scopeKey)
        let snapshots = loadHistories()[historyKey]?.snapshots ?? []
        guard !snapshots.isEmpty else {
            return []
        }

        var entries: [DailyCostEntry] = []
        var previousCumulative = 0
        var previousCategoryCumulative: [String: Int] = [:]

        for snapshot in snapshots {
            let dailyCents = max(0, snapshot.cumulativeCents - previousCumulative)
            guard let date = dayDate(from: snapshot.dayKey, calendar: calendar) else {
                continue
            }

            var segments: [DailyCostCategorySegment] = []
            if let categoryCents = snapshot.categoryCents, !categoryCents.isEmpty {
                for (categoryKey, cumulative) in categoryCents {
                    let previous = previousCategoryCumulative[categoryKey] ?? 0
                    let dailyCategoryCents = max(0, cumulative - previous)
                    guard dailyCategoryCents > 0,
                          let category = DailyCostCategory(rawValue: categoryKey) else {
                        continue
                    }

                    segments.append(
                        DailyCostCategorySegment(category: category, costCents: dailyCategoryCents)
                    )
                }

                segments.sort { $0.category.sortOrder < $1.category.sortOrder }
            }

            entries.append(DailyCostEntry(date: date, costCents: dailyCents, segments: segments))
            previousCumulative = snapshot.cumulativeCents

            if let categoryCents = snapshot.categoryCents {
                for (key, value) in categoryCents {
                    previousCategoryCumulative[key] = value
                }
            }
        }

        return entries
    }

    static func historyKey(periodKey: String, scopeKey: String) -> String {
        "\(periodKey)|\(scopeKey)"
    }

    private func loadHistories() -> [String: StoredHistory] {
        guard let data = defaults.data(forKey: storageKey),
              let histories = try? JSONDecoder().decode([String: StoredHistory].self, from: data) else {
            return [:]
        }

        return histories
    }

    private func saveHistories(_ histories: [String: StoredHistory]) {
        guard let data = try? JSONEncoder().encode(histories) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    private func dayDate(from dayKey: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayKey)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
