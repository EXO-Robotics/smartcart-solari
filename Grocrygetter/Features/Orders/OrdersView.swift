import SwiftUI

struct OrdersView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header

                if appModel.reservations.isEmpty {
                    nextPickupPreview
                } else {
                    ForEach(appModel.reservations) { reservation in
                        ReservationCard(reservation: reservation)
                    }
                }

                deliveryPartnersSection
                howItWorks
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .background(GatherTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Plans & handoffs")
                    .font(.headline)
                    .foregroundStyle(GatherTheme.ink)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Your food,")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(GatherTheme.ink)
            Text("already on the way.")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(GatherTheme.tomato)
        }
        .padding(.top, 8)
    }

    private var nextPickupPreview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ready when you are")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Reserve a pickup window from your smart cart.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer()

                Image(systemName: "car.side.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(GatherTheme.butter)
            }

            Button {
                appModel.selectedTab = .cart
            } label: {
                HStack {
                    Text("Go to cart")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GatherTheme.herb)
                .padding(14)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(20)
        .background {
            LinearGradient(
                colors: [GatherTheme.herb, Color(red: 0.28, green: 0.49, blue: 0.31)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .gatherShadow()
    }

    private var deliveryPartnersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Delivery connections")

            ForEach(appModel.deliveryPartners) { partner in
                Button {
                    appModel.connect(partner)
                    if let url = partner.url {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: partner.symbol)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(partner.color)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(partner.name)
                            .font(.headline)
                            .foregroundStyle(GatherTheme.ink)

                        Spacer()

                        Text(appModel.connectedPartnerName == partner.name ? "Connected" : "Link")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(appModel.connectedPartnerName == partner.name ? GatherTheme.herb : GatherTheme.secondaryInk)

                        Image(systemName: appModel.connectedPartnerName == partner.name ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(appModel.connectedPartnerName == partner.name ? GatherTheme.herb : Color.gray.opacity(0.5))
                    }
                    .gatherCard(padding: 14)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "How Gather checks out")

            stepRow(number: "1", title: "Builds the cart", message: "Recipe ingredients are matched and pantry basics are skipped.")
            stepRow(number: "2", title: "Finds the best route", message: "Use one store or split the list to save time and money.")
            stepRow(number: "3", title: "Hands off securely", message: "You review retailer substitutions and payment before final checkout.")
        }
        .gatherCard()
    }

    private func stepRow(number: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(GatherTheme.herb)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GatherTheme.ink)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ReservationCard: View {
    let reservation: PickupReservation

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pickup confirmed")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GatherTheme.herb)
                        .textCase(.uppercase)
                    Text("\(reservation.day), \(reservation.time)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(GatherTheme.ink)
                }

                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(GatherTheme.herb)
            }

            HStack(spacing: 12) {
                Image(systemName: "storefront.fill")
                    .foregroundStyle(GatherTheme.tomato)
                    .frame(width: 43, height: 43)
                    .background(GatherTheme.peach.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(reservation.storeName)
                        .font(.headline)
                        .foregroundStyle(GatherTheme.ink)
                    Text("\(reservation.itemCount) items • \(reservation.confirmation)")
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }

                Spacer()

                Text("$\(reservation.total, specifier: "%.2f")")
                    .font(.headline)
                    .foregroundStyle(GatherTheme.ink)
            }

            HStack {
                Label("We’ll remind you 30 min before", systemImage: "bell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GatherTheme.secondaryInk)
                Spacer()
                Button("Details") {}
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GatherTheme.herb)
            }
        }
        .gatherCard()
        .gatherShadow()
    }
}
