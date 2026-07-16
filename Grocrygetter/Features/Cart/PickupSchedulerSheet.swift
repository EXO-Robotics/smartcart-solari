import SwiftUI

struct PickupSchedulerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var appModel
    @State private var mode: FulfillmentMode = .pickup
    @State private var selectedDay = "Today"
    @State private var selectedTime = "5:30 PM"

    private let days = ["Today", "Tomorrow", "Saturday"]
    private let times = ["4:30 PM", "5:30 PM", "6:00 PM", "7:30 PM"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    fulfillmentPicker

                    if mode == .pickup {
                        pickupContent
                    } else {
                        deliveryContent
                    }
                }
                .padding(20)
                .padding(.bottom, 92)
            }
            .background(GatherTheme.canvas)
            .navigationTitle("Finish your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomAction
            }
        }
        .presentationDetents([.large])
    }

    private var fulfillmentPicker: some View {
        Picker("Fulfillment", selection: $mode) {
            ForEach(FulfillmentMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var pickupContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Choose a day")
                HStack(spacing: 9) {
                    ForEach(days, id: \.self) { day in
                        ChoiceChip(title: day, isSelected: selectedDay == day) {
                            selectedDay = day
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Pickup window")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(times, id: \.self) { time in
                        ChoiceChip(title: time, isSelected: selectedTime == time) {
                            selectedTime = time
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Stops in your route")
                ForEach(appModel.selectedStores) { store in
                    HStack(spacing: 13) {
                        StoreMark(store: store, size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.name)
                                .font(.headline)
                                .foregroundStyle(GatherTheme.ink)
                            Text(store.pickupFee == 0 ? "Free pickup" : "$\(store.pickupFee, specifier: "%.2f") pickup")
                                .font(.caption)
                                .foregroundStyle(GatherTheme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(GatherTheme.herb)
                    }
                    .gatherCard(padding: 14)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(GatherTheme.tomato)
                Text("Gather will stagger multi-store pickups by 15 minutes to keep your route easy.")
                    .font(.subheadline)
                    .foregroundStyle(GatherTheme.secondaryInk)
            }
            .padding(16)
            .background(GatherTheme.peach.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var deliveryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Send your cart")
            Text("Link a delivery partner, then Gather will prepare a retailer-ready handoff for final availability and checkout.")
                .font(.subheadline)
                .foregroundStyle(GatherTheme.secondaryInk)

            ForEach(appModel.deliveryPartners) { partner in
                Button {
                    appModel.connect(partner)
                    if let url = partner.url {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: partner.symbol)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(partner.color)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(partner.name)
                                .font(.headline)
                                .foregroundStyle(GatherTheme.ink)
                            Text(appModel.connectedPartnerName == partner.name ? "Connected" : partner.status)
                                .font(.caption)
                                .foregroundStyle(appModel.connectedPartnerName == partner.name ? GatherTheme.herb : GatherTheme.secondaryInk)
                        }

                        Spacer()

                        Image(systemName: appModel.connectedPartnerName == partner.name ? "checkmark.circle.fill" : "arrow.up.right")
                            .foregroundStyle(appModel.connectedPartnerName == partner.name ? GatherTheme.herb : GatherTheme.secondaryInk)
                    }
                    .gatherCard(padding: 14)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if mode == .pickup {
                    appModel.reservePickup(day: selectedDay, time: selectedTime)
                } else if let partner = appModel.deliveryPartners.first(where: { $0.name == appModel.connectedPartnerName }),
                          let url = partner.url {
                    openURL(url)
                    dismiss()
                } else {
                    appModel.showToast("Choose a delivery partner first")
                }
            } label: {
                HStack {
                    Text(mode == .pickup ? "Reserve pickup" : "Open delivery partner")
                    Spacer()
                    Image(systemName: mode == .pickup ? "calendar.badge.checkmark" : "arrow.up.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(16)
            .background(.ultraThinMaterial)
        }
    }
}

private struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : GatherTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(isSelected ? GatherTheme.herb : GatherTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(GatherTheme.border, lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(PressableButtonStyle())
    }
}
