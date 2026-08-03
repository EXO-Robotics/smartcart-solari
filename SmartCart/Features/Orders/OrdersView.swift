import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SmartCartAppearanceController.self) private var appearanceController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                accountHeader
                retailerAndLocationCard
                appearanceCard
                preferenceCard
                #if DEBUG
                testerModeCard
                if appModel.featureFlags.internalTesterModeEnabled {
                    testerDashboard
                }
                #endif
                if let issue = appModel.persistenceIssue {
                    InfoBanner(
                        symbol: "externaldrive.badge.exclamationmark",
                        title: "Could not save local state",
                        message: issue,
                        color: SmartCartTheme.coral
                    )
                }
                privacyCard
                aboutCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
        .smartCartBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var cleanLightModeEnabled: Binding<Bool> {
        Binding(
            get: { appearanceController.cleanLightModeEnabled },
            set: { appearanceController.cleanLightModeEnabled = $0 }
        )
    }

    private var appearanceCard: some View {
        Toggle(isOn: cleanLightModeEnabled) {
            HStack(spacing: 13) {
                Image(systemName: cleanLightModeEnabled.wrappedValue ? "sun.max.fill" : "moon.stars.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(width: 42, height: 42)
                    .background(SmartCartTheme.herbLight)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Clean light theme")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(
                        cleanLightModeEnabled.wrappedValue
                            ? SmartCartAppearance.cleanLight.subtitle
                            : "Off · \(SmartCartAppearance.midnight.subtitle)"
                    )
                    .font(.caption)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }
        }
        .tint(SmartCartTheme.green)
        .accessibilityIdentifier("smartcart.appearance.cleanLight")
        .smartCartCard()
    }

    private var retailerAndLocationCard: some View {
        NavigationLink {
            StoreDashboardView()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "storefront.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .frame(width: 42, height: 42)
                    .background(SmartCartTheme.herbLight)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Retailer & location")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text(retailerProfileSummary)
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .smartCartCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile-retailer-location")
        .accessibilityHint("Opens retailer and nearby store settings")
    }

    private var retailerProfileSummary: String {
        guard appModel.resolvedStorePostalCode != nil else {
            return "Choose a store near your ZIP code"
        }
        if appModel.selectedRetailer == .walmart {
            return "\(appModel.retailerConfiguration.displayName) · \(appModel.primaryStore.name)"
        }
        return "\(appModel.retailerConfiguration.displayName) · Store confirmed by retailer"
    }

    private var accountHeader: some View {
        HStack(spacing: 15) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(SmartCartTheme.navy)

            VStack(alignment: .leading, spacing: 4) {
                Text("SmartCart shopper")
                    .font(.title2.bold())
                    .foregroundStyle(SmartCartTheme.navy)
                Text("Your shopping profile")
                    .font(.subheadline)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
                StatusPill(title: "Private on device", symbol: "lock.fill")
            }
        }
        .padding(.top, 8)
    }

    private var preferenceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(
                title: "Shopping preferences",
                subtitle: appModel.preferences.summary
            )
            ShoppingPreferenceControls()
        }
    }

    #if DEBUG
    private var testerModeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(
                isOn: Binding(
                    get: { appModel.featureFlags.internalTesterModeEnabled },
                    set: { appModel.setInternalTesterModeEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Internal tester mode")
                        .font(.headline)
                        .foregroundStyle(SmartCartTheme.navy)
                    Text("Show the on-device funnel, import quality, and connector readiness.")
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                }
            }
            .tint(SmartCartTheme.green)

            Toggle(
                "Record anonymous events on this device",
                isOn: Binding(
                    get: { appModel.featureFlags.localAnalyticsEnabled },
                    set: { appModel.setLocalAnalyticsEnabled($0) }
                )
            )
            .font(.subheadline.weight(.semibold))
            .tint(SmartCartTheme.green)
        }
        .smartCartCard()
    }

    private var testerDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(
                    title: "Closed-beta funnel",
                    subtitle: "Local diagnostic events only · no recipe text or UPC values"
                )
                Spacer()
                Button("Clear") { appModel.clearLocalAnalytics() }
                    .font(.caption.weight(.bold))
            }

            let importCount = eventCount(.importStarted)
            let extractionCount = eventCount(.extractionCompleted)
            let matchCount = eventCount(.matchingCompleted)
            let handoffCount = eventCount(.retailerLinkOpened)

            HStack(spacing: 8) {
                testerMetric("Imports", value: importCount)
                testerMetric("Extracted", value: extractionCount)
                testerMetric("Matched", value: matchCount)
                testerMetric("Retailer opens", value: handoffCount)
            }

            if let report = appModel.lastImportReport {
                InfoBanner(
                    symbol: "waveform.path.ecg",
                    title: "Last import · \(report.confidenceLabel)",
                    message: "\(report.sourcePageCount) page(s), \(report.ingredientLineCount) ingredients, \(report.reviewCount) review item(s), evidence preserved for \(report.sourceEvidenceCount), \(report.quantityAlternativeReviewCount) quantity alternative(s), layout \(report.layoutConfidence.formatted(.percent.precision(.fractionLength(0)))) with \(report.layoutAmbiguityCount) ambiguity flag(s), \(report.ignoredInstructionLineCount) instruction line(s) excluded, \(report.retryCount) OCR retry/retries, \(report.duration.formatted(.number.precision(.fractionLength(2))))s.",
                    color: report.confidenceScore >= 0.82 ? SmartCartTheme.green : SmartCartTheme.amber
                )
            }
        }
        .smartCartCard()
    }

    private func eventCount(_ name: AnalyticsEventName) -> Int {
        appModel.analyticsEvents.filter { $0.name == name }.count
    }

    private func testerMetric(_ title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.bold())
                .foregroundStyle(SmartCartTheme.green)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SmartCartTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(SmartCartTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    #endif

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(title: "Trust & privacy")
            trustRow("No retailer credentials", "key.slash.fill")
            trustRow("No payment data stored", "creditcard.trianglebadge.exclamationmark")
            trustRow("On-device photo text recognition", "text.viewfinder")
            trustRow("Retailer confirms final checkout", "checkmark.shield.fill")
        }
        .smartCartCard()
    }

    private func trustRow(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(SmartCartTheme.green)
                .frame(width: 26)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SmartCartTheme.navy)
        }
    }

    private var aboutCard: some View {
        HStack {
            SmartCartLogo(compact: true)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SmartCart")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SmartCartTheme.navy)
                Text(SmartCartBuildInfo.displayVersion())
                    .font(.caption2)
                    .foregroundStyle(SmartCartTheme.secondaryInk)
            }
        }
        .smartCartCard(padding: 14)
    }
}
