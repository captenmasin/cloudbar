import SwiftUI

enum SettingsCredits {
    static let authorURL = URL(string: "https://masondoes.dev/")!
}

struct BuiltByMasonLink: View {
    var body: some View {
        Link("Built by mason", destination: SettingsCredits.authorURL)
    }
}

struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    CloudBarLogo(size: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CloudBar")
                            .font(.largeTitle.bold())

                        Text(AppVersion.displayString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("A menu bar companion for Laravel Cloud usage.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("About") {
                Text("CloudBar shows your current Laravel Cloud spend, bandwidth, resources, and application compute from the menu bar.")
                    .foregroundStyle(.secondary)

                BuiltByMasonLink()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}
