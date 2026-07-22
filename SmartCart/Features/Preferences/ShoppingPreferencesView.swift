import SwiftUI

struct ShoppingPreferenceControls: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 16) {
            preferenceSection(
                title: "Organic",
                message: appModel.preferences.organicPolicy.explanation
            ) {
                Picker("Organic policy", selection: $appModel.preferences.organicPolicy) {
                    ForEach(OrganicPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .tint(SmartCartTheme.green)
            }

            Divider()

            preferenceSection(
                title: "Budget",
                message: budgetExplanation
            ) {
                Picker("Budget priority", selection: $appModel.preferences.budgetPriority) {
                    ForEach(BudgetPriority.allCases) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                .pickerStyle(.menu)
                .tint(SmartCartTheme.green)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("DIETARY HARD FILTERS")
                    .smartEyebrow(SmartCartTheme.mutedInk)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 126), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(DietaryAttribute.allCases) { attribute in
                        let selected = appModel.preferences.dietaryRestrictions.contains(attribute)
                        Button {
                            if selected {
                                appModel.preferences.dietaryRestrictions.remove(attribute)
                            } else {
                                appModel.preferences.dietaryRestrictions.insert(attribute)
                            }
                        } label: {
                            Label(
                                attribute.label,
                                systemImage: selected ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selected ? SmartCartTheme.onAccent : SmartCartTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .background(selected ? SmartCartTheme.green : SmartCartTheme.canvasRaise)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected ? Color.clear : SmartCartTheme.border, lineWidth: 1)
                            }
                            .shadow(color: selected ? SmartCartTheme.mintGlow : .clear, radius: 8)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }

            Divider()

            preferenceSection(
                title: "Store brand",
                message: "Applied after product correctness, availability, package fit, and purchase price."
            ) {
                Picker("Store brand", selection: $appModel.preferences.storeBrandPreference) {
                    ForEach(StoreBrandPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.menu)
                .tint(SmartCartTheme.green)
            }
        }
        .smartCartCard()
    }

    private var budgetExplanation: String {
        switch appModel.preferences.budgetPriority {
        case .lowestTotal:
            "Ranks the lowest eligible package total first."
        case .balanced:
            "Balances purchase price with product and package fit."
        case .qualityFirst:
            "Favors exact, well-supported product records before price."
        }
    }

    private func preferenceSection<Content: View>(
        title: String,
        message: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
                Spacer(minLength: 8)
                control()
            }
        }
    }
}
