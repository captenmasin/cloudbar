import SwiftUI

struct AccountSettingsPane: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var tokenDraft = ""
    @State private var isSaving = false
    @State private var selectedCurrencyCode = "USD"

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Laravel Cloud API Token")
                    Text("Create a token in Laravel Cloud under your profile settings. CloudBar stores it securely in the Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("Bearer token", text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)

                if viewModel.hasToken {
                    LabeledContent("Saved token") {
                        Text(viewModel.maskedToken)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button("Save Token") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            await viewModel.saveToken(tokenDraft)
                            tokenDraft = viewModel.maskedToken
                            await viewModel.refresh()
                        }
                    }
                    .controlSize(.small)
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                    Button("Clear Token") {
                        Task {
                            await viewModel.clearToken()
                            tokenDraft = ""
                        }
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.hasToken || isSaving)
                }

                if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Display currency", selection: $selectedCurrencyCode) {
                    ForEach(SupportedCurrency.allCases) { currency in
                        Text("\(currency.rawValue) – \(currency.title)")
                            .tag(currency.rawValue)
                    }
                }
                .pickerStyle(.menu)

                if let billingCurrency = billingCurrencyLabel {
                    LabeledContent("Billing currency") {
                        Text(billingCurrency)
                            .foregroundStyle(.secondary)
                    }
                }

                if let conversionDescription = viewModel.currencyConversionDescription {
                    Text(conversionDescription)
                        .font(.caption)
                        .foregroundStyle(viewModel.exchangeRateUnavailable ? .orange : .secondary)
                }
            } header: {
                Text("Currency")
            } footer: {
                Text("Spend amounts are converted from your Laravel Cloud billing currency into the display currency you choose.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .onAppear {
            tokenDraft = viewModel.maskedToken
            selectedCurrencyCode = viewModel.displayCurrency
        }
        .onChange(of: selectedCurrencyCode) { _, newValue in
            Task {
                await viewModel.setDisplayCurrency(newValue)
            }
        }
        .onChange(of: viewModel.displayCurrency) { _, newValue in
            if selectedCurrencyCode != newValue {
                selectedCurrencyCode = newValue
            }
        }
    }

    private var billingCurrencyLabel: String? {
        guard viewModel.usage != nil else { return nil }
        return viewModel.billingCurrency
    }
}
