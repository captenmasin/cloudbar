import AppKit
import SwiftUI

@main
struct CloudBarApp: App {
    @StateObject private var viewModel = UsageViewModel(client: LaravelCloudClient())

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(viewModel: viewModel)
                .frame(width: 420)
                .task {
                    await viewModel.loadSavedToken()
                    await viewModel.refresh()
                }
        } label: {
            MenuBarLabel(title: viewModel.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let title: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let icon = NSImage.cloudBarLogo {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "cloud")
            }
        }
    }
}

extension NSImage {
    static var cloudBarLogo: NSImage? {
        let image = NSImage(size: NSSize(width: 16, height: 16))

        image.lockFocus()
        NSColor.black.setFill()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 15, y: 5.67))
        path.line(to: NSPoint(x: 10.33, y: 1))
        path.line(to: NSPoint(x: 1, y: 1))
        path.line(to: NSPoint(x: 1, y: 10.33))
        path.line(to: NSPoint(x: 5.67, y: 15))
        path.line(to: NSPoint(x: 15, y: 15))
        path.close()

        path.move(to: NSPoint(x: 5.67, y: 12.2))
        path.line(to: NSPoint(x: 5.67, y: 11.27))
        path.line(to: NSPoint(x: 11.27, y: 11.27))
        path.line(to: NSPoint(x: 11.27, y: 5.67))
        path.line(to: NSPoint(x: 12.2, y: 5.67))
        path.line(to: NSPoint(x: 12.2, y: 12.2))
        path.close()

        path.move(to: NSPoint(x: 5.67, y: 13.13))
        path.line(to: NSPoint(x: 13.14, y: 13.13))
        path.line(to: NSPoint(x: 13.14, y: 5.66))
        path.line(to: NSPoint(x: 14.07, y: 5.66))
        path.line(to: NSPoint(x: 14.07, y: 14.07))
        path.line(to: NSPoint(x: 5.67, y: 14.07))
        path.close()

        path.move(to: NSPoint(x: 5.67, y: 10.33))
        path.line(to: NSPoint(x: 5.67, y: 5.66))
        path.line(to: NSPoint(x: 10.34, y: 5.66))
        path.line(to: NSPoint(x: 10.34, y: 10.33))
        path.close()

        path.fill()
        image.unlockFocus()

        image.isTemplate = true
        return image
    }
}

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var tokenDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.hasToken {
                applicationSelector
                usageContent
            } else {
                tokenForm
            }

            Divider()

            controls
        }
        .padding(16)
        .onAppear {
            tokenDraft = viewModel.maskedToken
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Laravel Cloud")
                    .font(.headline)
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let billingPeriodText = viewModel.billingPeriodText {
                    Text(billingPeriodText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var usageContent: some View {
        if let usage = viewModel.usage {
            VStack(alignment: .leading, spacing: 12) {
                MetricRow(
                    title: "Current spend",
                    value: viewModel.money(viewModel.displayedCurrentSpendCents),
                    systemImage: "creditcard"
                )

                MetricRow(
                    title: "Bandwidth",
                    value: viewModel.percent(viewModel.displayedBandwidth?.usagePercentage),
                    detail: bandwidthDetail(usage),
                    systemImage: "arrow.up.arrow.down"
                )

                MetricRow(
                    title: "Resources",
                    value: viewModel.money(viewModel.displayedResourcesTotalCents),
                    systemImage: "server.rack"
                )

                MetricRow(
                    title: "Applications",
                    value: viewModel.money(viewModel.displayedApplicationTotalCents),
                    detail: viewModel.applicationCountText,
                    systemImage: "app.connected.to.app.below.fill"
                )

                applicationClusters
                resources(usage)
                addons(usage)

                if let alertText = viewModel.alertText {
                    Label(alertText, systemImage: "bell.badge")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } else if let errorMessage = viewModel.errorMessage {
            EmptyStateView(
                title: "Unable to Load Usage",
                message: errorMessage,
                systemImage: "exclamationmark.triangle"
            )
        } else {
            EmptyStateView(
                title: "No Usage Loaded",
                message: "Refresh to fetch your current Laravel Cloud usage.",
                systemImage: "cloud"
            )
        }
    }

    private var applicationSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Application", selection: $viewModel.selectedApplicationID) {
                Text("All applications").tag("")
                ForEach(viewModel.applicationOptions) { application in
                    Text(application.name).tag(application.id)
                }
            }
            .disabled(viewModel.applicationOptions.isEmpty)
            .onChange(of: viewModel.selectedApplicationID) { _ in
                Task { await viewModel.loadSelectedApplicationCompute() }
            }

            selectedApplicationActions
        }
    }

    private var tokenForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste a Laravel Cloud API token to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Bearer token", text: $tokenDraft)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    await viewModel.saveToken(tokenDraft)
                    tokenDraft = viewModel.maskedToken
                    await viewModel.refresh()
                }
            } label: {
                Label("Save Token", systemImage: "key")
            }
            .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    openOrganizationOverview()
                } label: {
                    Label("Organization", systemImage: "building.2")
                }

                Spacer()

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!viewModel.hasToken || viewModel.isLoading)
            }
        }
    }

    @ViewBuilder
    private var selectedApplicationActions: some View {
        if viewModel.selectedApplication != nil {
            HStack {
                Button {
                    viewModel.open(viewModel.selectedDeployURL)
                } label: {
                    Label("Deploy", systemImage: "paperplane")
                }
                .disabled(viewModel.selectedDeployURL == nil)

                Button {
                    viewModel.open(viewModel.selectedVisitURL)
                } label: {
                    Label("Visit", systemImage: "safari")
                }
                .disabled(viewModel.selectedVisitURL == nil)

                Button {
                    viewModel.open(viewModel.selectedRepositoryURL)
                } label: {
                    Label("View repo", systemImage: "curlybraces.square")
                }
                .disabled(viewModel.selectedRepositoryURL == nil)
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var applicationClusters: some View {
        let groups = viewModel.clusterGroups.filter { !$0.1.isEmpty }
        UsageSection(title: "Application compute", systemImage: "cpu", total: nil) {
            if viewModel.isLoadingApplicationCompute {
                Text("Loading compute usage...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if groups.isEmpty {
                Text("No cluster usage for \(viewModel.displayedApplicationName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups, id: \.0) { group in
                    MiniGroup(title: group.0.title, items: group.1, viewModel: viewModel)
                }
            }
        }
    }

    private func resources(_ usage: UsageResponse) -> some View {
        UsageSection(
            title: "Resources",
            systemImage: "server.rack",
            total: viewModel.money(viewModel.displayedResourcesTotalCents)
        ) {
            ResourceCategoryRow(
                title: "Databases",
                systemImage: "cylinder.split.1x2",
                items: viewModel.displayedDatabaseItems,
                viewModel: viewModel
            )
            ResourceCategoryRow(
                title: "Caches",
                systemImage: "memorychip",
                items: viewModel.displayedCacheItems,
                viewModel: viewModel
            )
            ResourceCategoryRow(
                title: "Buckets",
                systemImage: "shippingbox",
                items: viewModel.displayedBucketItems,
                viewModel: viewModel
            )
            ResourceCategoryRow(
                title: "WebSockets",
                systemImage: "point.3.connected.trianglepath.dotted",
                items: viewModel.displayedWebSocketItems,
                viewModel: viewModel
            )
        }
    }

    @ViewBuilder
    private func addons(_ usage: UsageResponse) -> some View {
        if usage.data.addons != nil {
            UsageSection(
                title: "Add-ons",
                systemImage: "puzzlepiece.extension",
                total: viewModel.money(viewModel.displayedAddonsTotalCents)
            ) {
                let items = viewModel.displayedAddonItems
                if !items.isEmpty {
                    ForEach(items) { item in
                        CostLine(title: item.name, subtitle: nil, value: viewModel.money(item.totalCents))
                    }
                } else {
                    Text("No add-on line items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func openOrganizationOverview() {
        guard let url = URL(string: "https://cloud.laravel.com") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func bandwidthDetail(_ usage: UsageResponse) -> String? {
        guard let bandwidth = viewModel.displayedBandwidth else {
            return nil
        }

        let cost = viewModel.money(bandwidth.costCents)
        guard let allowance = bandwidth.allowanceBytes else {
            return cost
        }

        return "\(cost) of \(ByteCountFormatter.string(fromByteCount: allowance, countStyle: .file))"
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    var detail: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

struct UsageSection<Content: View>: View {
    let title: String
    let systemImage: String
    let total: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let total {
                    Text(total)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }

            content
        }
        .padding(.vertical, 4)
    }
}

struct ResourceCategoryRow: View {
    let title: String
    let systemImage: String
    let items: [UsageLineItem]
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(countText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(viewModel.money(categoryTotalCents))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var countText: String {
        guard !items.isEmpty else {
            return "No resources"
        }

        return "\(items.count) resource\(items.count == 1 ? "" : "s")"
    }

    private var categoryTotalCents: Int? {
        let totals = items.compactMap(\.totalCostCents)
        guard !totals.isEmpty else {
            return nil
        }

        return totals.reduce(0, +)
    }
}

struct MiniGroup: View {
    let title: String
    let items: [UsageLineItem]
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(countText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(viewModel.money(groupTotalCents))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var countText: String {
        "\(items.count) resource\(items.count == 1 ? "" : "s")"
    }

    private var groupTotalCents: Int? {
        let totals = items.compactMap(\.totalCostCents)
        guard !totals.isEmpty else {
            return nil
        }

        return totals.reduce(0, +)
    }
}

struct CostLine: View {
    let title: String
    let subtitle: String?
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
