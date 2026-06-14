import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case cloudBar
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .cloudBar: "CloudBar"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .cloudBar: "cloud"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    @Published var selectedTab: SettingsTab? = .cloudBar

    private init() {}
}

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var navigation = SettingsNavigation.shared
    @State private var navigationHistory: [SettingsTab] = [.cloudBar]
    @State private var historyIndex = 0
    @State private var isHistoryNavigation = false

    private var activeTab: SettingsTab {
        navigation.selectedTab ?? .cloudBar
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebarView(selectedTab: $navigation.selectedTab)
                .frame(width: 200)
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailView(viewModel: viewModel, tab: activeTab)
        }
        .navigationTitle("CloudBar Settings")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, minHeight: 540)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)

                Button {
                    goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
            }
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            recordNavigation()
        }
    }

    private var canGoBack: Bool {
        historyIndex > 0
    }

    private var canGoForward: Bool {
        historyIndex < navigationHistory.count - 1
    }

    private func goBack() {
        guard canGoBack else { return }
        isHistoryNavigation = true
        historyIndex -= 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func goForward() {
        guard canGoForward else { return }
        isHistoryNavigation = true
        historyIndex += 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func recordNavigation() {
        guard !isHistoryNavigation else { return }
        guard let tab = navigation.selectedTab else { return }
        if navigationHistory.last == tab { return }
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(tab)
        historyIndex = navigationHistory.count - 1
    }
}

private struct SettingsSidebarView: View {
    @Binding var selectedTab: SettingsTab?

    var body: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    SettingsTabIcon(tab: tab)
                }
                .foregroundStyle(.primary)
                .tag(tab)
            }

            SettingsSidebarFooter()
        }
        .listStyle(.sidebar)
        .navigationTitle("CloudBar Settings")
    }
}

private struct SettingsTabIcon: View {
    let tab: SettingsTab

    var body: some View {
        switch tab {
        case .cloudBar:
            LaravelCloudLogo(size: 16)
        case .about:
            Image(systemName: tab.systemImage)
        }
    }
}

private struct SettingsSidebarFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppVersion.displayString)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fontDesign(.monospaced)

            BuiltByMasonLink()
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0))
    }
}

private struct SettingsDetailView: View {
    @ObservedObject var viewModel: UsageViewModel
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .cloudBar:
                AccountSettingsPane(viewModel: viewModel)
            case .about:
                AboutSettingsPane()
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
