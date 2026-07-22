import SwiftUI

struct WeeklyMealMagnifyingCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedID: CuratedRecipeID?
    @State private var userDragPendingFocus = false
    @State private var focusFeedbackCount = 0

    let models: [WeeklyMealDisplayModel]
    let onOpen: (CuratedRecipeID) -> Void
    let onShop: (CuratedRecipeID) -> Void

    var body: some View {
        let reduceMotionEnabled = reduceMotion
        GeometryReader { proxy in
            let cardWidth = WeeklyMealCarouselLayout.cardWidth(containerWidth: proxy.size.width)
            let edgeMargin = WeeklyMealCarouselLayout.edgeMargin(
                containerWidth: proxy.size.width,
                cardWidth: cardWidth
            )

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(models) { model in
                        WeeklyMealCard(
                            model: model,
                            isFocused: focusedID == model.id,
                            fixedHeight: 468,
                            onOpen: { onOpen(model.id) },
                            onShop: { onShop(model.id) }
                        )
                        .frame(width: cardWidth)
                        .id(model.id)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(reduceMotionEnabled ? 1 : WeeklyMealCarouselLayout.scale(phase: phase.value))
                                .opacity(WeeklyMealCarouselLayout.opacity(phase: phase.value, reduceMotion: reduceMotionEnabled))
                                .offset(y: reduceMotionEnabled ? 0 : WeeklyMealCarouselLayout.verticalOffset(phase: phase.value))
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, edgeMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusedID, anchor: .center)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in userDragPendingFocus = true }
            )
            .onChange(of: focusedID) { oldValue, newValue in
                guard oldValue != nil, oldValue != newValue, userDragPendingFocus else { return }
                userDragPendingFocus = false
                focusFeedbackCount += 1
            }
            .sensoryFeedback(.selection, trigger: focusFeedbackCount)
        }
        .frame(height: 492)
        .onAppear {
            if focusedID == nil {
                focusedID = models.first(where: \.isFeatured)?.id ?? models.first?.id
            }
        }
        .overlay(alignment: .bottom) {
            positionIndicator
        }
    }

    private var positionIndicator: some View {
        HStack(spacing: 5) {
            ForEach(models) { model in
                Capsule()
                    .fill(focusedID == model.id ? SmartCartTheme.green : SmartCartTheme.mutedInk.opacity(0.35))
                    .frame(width: focusedID == model.id ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : SmartCartMotion.quick, value: focusedID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(positionAccessibilityLabel)
    }

    private var positionAccessibilityLabel: String {
        guard let focusedID,
              let index = models.firstIndex(where: { $0.id == focusedID }) else {
            return "Eight weekly meals"
        }
        return "Meal \(index + 1) of \(models.count)"
    }

}

enum WeeklyMealCarouselLayout {
    static func cardWidth(containerWidth: CGFloat) -> CGFloat {
        min(360, containerWidth * 0.84)
    }

    static func edgeMargin(containerWidth: CGFloat, cardWidth: CGFloat) -> CGFloat {
        max(0, (containerWidth - cardWidth) / 2)
    }

    static func scale(phase: CGFloat) -> CGFloat {
        1 - min(abs(phase), 1) * 0.07
    }

    static func opacity(phase: CGFloat, reduceMotion: Bool) -> CGFloat {
        1 - min(abs(phase), 1) * (reduceMotion ? 0.10 : 0.16)
    }

    static func verticalOffset(phase: CGFloat) -> CGFloat {
        min(abs(phase), 1) * 7
    }
}
