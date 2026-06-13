import AppKit
import SwiftUI

@main
struct CloudBarApp: App {
    @StateObject private var viewModel = UsageViewModel(client: LaravelCloudClient())

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(viewModel: viewModel)
                .frame(width: 340)
                .task {
                    await viewModel.loadSavedToken()
                    await viewModel.refresh()
                }
        } label: {
            Label(viewModel.menuBarTitle, systemImage: viewModel.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var tokenDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.hasToken {
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
                    value: viewModel.money(usage.data.summary.currentSpendCents),
                    systemImage: "creditcard"
                )

                MetricRow(
                    title: "Bandwidth",
                    value: viewModel.percent(usage.data.summary.bandwidth?.usagePercentage),
                    detail: bandwidthDetail(usage),
                    systemImage: "arrow.up.arrow.down"
                )

                MetricRow(
                    title: "Resources",
                    value: viewModel.money(usage.data.resources?.totalCostCents),
                    systemImage: "server.rack"
                )

                MetricRow(
                    title: "Applications",
                    value: viewModel.money(usage.data.applicationTotals?.totalCostCents),
                    detail: viewModel.applicationCountText,
                    systemImage: "app.connected.to.app.below.fill"
                )

                MetricRow(
                    title: "Add-ons",
                    value: viewModel.money(usage.data.addons?.totalCostCents),
                    systemImage: "shippingbox"
                )

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
            Picker("Billing period", selection: $viewModel.period) {
                Text("Current").tag(0)
                Text("Previous").tag(1)
                Text("2 periods ago").tag(2)
                Text("3 periods ago").tag(3)
            }

            TextField("Environment ID or slug (optional)", text: $viewModel.environment)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!viewModel.hasToken || viewModel.isLoading)

                Spacer()

                Button {
                    Task {
                        await viewModel.clearToken()
                        tokenDraft = ""
                    }
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(!viewModel.hasToken)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
        }
    }

    private func bandwidthDetail(_ usage: UsageResponse) -> String? {
        guard let bandwidth = usage.data.summary.bandwidth else {
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
