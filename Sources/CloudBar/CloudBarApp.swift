import AppKit
import SwiftUI

@main
struct CloudBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: UsageViewModel!
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        CloudBarAppIcon.applyApplicationIcon()
        NSApp.setActivationPolicy(.accessory)

        viewModel = UsageViewModel(client: LaravelCloudClient())
        menuBarController = MenuBarController(viewModel: viewModel)

        viewModel.startAutoRefresh()

        Task {
            await viewModel.loadSavedToken()
            await viewModel.refresh()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.hasToken {
                applicationSelector
                usageContent
            } else {
                signInPrompt
            }

            Divider()

            controls
        }
        .padding(16)
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
                metricsGrid(usage: usage)

                applicationClusters
                resources(usage)
                addons(usage)

                if let alertText = viewModel.alertText {
                    UsageAlertBanner(text: alertText)
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
        Picker("Application", selection: $viewModel.selectedApplicationID) {
            Text("All applications").tag("")
            ForEach(viewModel.applicationOptions) { application in
                Text(application.name).tag(application.id)
            }
        }
        .disabled(viewModel.applicationOptions.isEmpty)
        .onChange(of: viewModel.selectedApplicationID) { _, _ in
            Task { await viewModel.loadSelectedApplicationCompute() }
        }
    }

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add your Laravel Cloud API token in Settings to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                SettingsWindowController.show(viewModel: viewModel, tab: .cloudBar)
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
        }
    }

    private func metricsGrid(usage: UsageResponse) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
        ) {
            MetricCard(
                title: "Current spend",
                value: viewModel.money(viewModel.displayedCurrentSpendCents),
                systemImage: "creditcard"
            )

            MetricCard(
                title: "Bandwidth",
                value: viewModel.percent(viewModel.displayedBandwidth?.usagePercentage),
                detail: viewModel.displayedBandwidth == nil ? nil : "of accrued allowance",
                progress: viewModel.displayedBandwidth?.usagePercentage,
                systemImage: "arrow.up.arrow.down"
            )

            MetricCard(
                title: "Resources",
                value: viewModel.money(viewModel.displayedResourcesTotalCents),
                systemImage: "server.rack"
            )

            MetricCard(
                title: "Applications",
                value: viewModel.money(viewModel.displayedApplicationTotalCents),
                detail: viewModel.applicationCountText,
                systemImage: "app.connected.to.app.below.fill"
            )
        }
    }

    private var controls: some View {
        HStack {
            if viewModel.hasInvalidToken {
                Button {
                    SettingsWindowController.show(viewModel: viewModel, tab: .cloudBar)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } else {
                Button {
                    openOrganizationUsage()
                } label: {
                    Label("See Organisation", systemImage: "building.2")
                }
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

    @ViewBuilder
    private var applicationClusters: some View {
        let groups = viewModel.clusterGroups.filter { !$0.1.isEmpty }
        UsageSection(
            title: "Application compute",
            systemImage: "cpu",
            total: viewModel.money(viewModel.displayedApplicationComputeTotalCents)
        ) {
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

    private func openOrganizationUsage() {
        guard let url = URL(string: "https://cloud.laravel.com/to/org/usage") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

}

struct UsageAlertBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    var detail: String?
    var progress: Double?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()

            if let progress {
                ProgressView(value: normalizedProgress(progress))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: progress == nil ? 52 : 64, alignment: .topLeading)
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }

    private func normalizedProgress(_ percentage: Double) -> Double {
        min(max(percentage / 100, 0), 1)
    }
}

struct UsageSection<Content: View>: View {
    let title: String
    let systemImage: String
    let total: String?
    @ViewBuilder var content: Content
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(.top, 2)
        } label: {
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
        }
        .padding(.vertical, 2)
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
