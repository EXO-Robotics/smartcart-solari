import SwiftUI

struct WeeklyMealMagnifyingCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedID: CuratedRecipeID?
    @State private var dragTranslation: CGFloat = 0
    @State private var horizontalDragActive = false
    @State private var userInteractionPendingFocus = false
    @State private var focusFeedbackCount = 0
    @State private var dwellTask: Task<Void, Never>?

    let models: [WeeklyMealDisplayModel]
    let onOpen: (CuratedRecipeID) -> Void
    let onShop: (CuratedRecipeID) -> Void
    let onFocused: (WeeklyMealDisplayModel) -> Void

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = WeeklyMealCarouselLayout.cardWidth(containerWidth: proxy.size.width)
            let focusedIndex = WeeklyMealCarouselLayout.focusedIndex(
                focusedID: focusedID,
                models: models
            )

            ZStack {
                ForEach(models) { model in
                    if let index = models.firstIndex(where: { $0.id == model.id }),
                       abs(index - focusedIndex) <= 1 {
                        rackCard(
                            model: model,
                            index: index,
                            focusedIndex: focusedIndex,
                            cardWidth: cardWidth
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: 468)
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(rackDragGesture(cardWidth: cardWidth))
            .overlay(alignment: .top) {
                rackArrows(focusedIndex: focusedIndex)
                    .padding(.top, 52)
            }
        }
        .frame(height: 492)
        .overlay(alignment: .bottom) {
            positionIndicator
        }
        .onAppear {
            if focusedID == nil {
                focusedID = models.first(where: \.isFeatured)?.id ?? models.first?.id
            }
            scheduleDwell(for: focusedID)
        }
        .onChange(of: focusedID) { oldValue, newValue in
            scheduleDwell(for: newValue)
            guard oldValue != nil,
                  oldValue != newValue,
                  userInteractionPendingFocus else { return }
            userInteractionPendingFocus = false
            focusFeedbackCount += 1
        }
        .sensoryFeedback(.selection, trigger: focusFeedbackCount)
        .onDisappear { dwellTask?.cancel() }
    }

    @ViewBuilder
    private func rackCard(
        model: WeeklyMealDisplayModel,
        index: Int,
        focusedIndex: Int,
        cardWidth: CGFloat
    ) -> some View {
        let relativeIndex = index - focusedIndex
        let transform = WeeklyMealCarouselLayout.rackTransform(
            relativeIndex: relativeIndex,
            dragTranslation: dragTranslation,
            cardWidth: cardWidth,
            reduceMotion: reduceMotion
        )

        WeeklyMealCard(
            model: model,
            isFocused: relativeIndex == 0,
            fixedHeight: 468,
            onOpen: { onOpen(model.id) },
            onShop: { onShop(model.id) }
        )
        .frame(width: cardWidth)
        .scaleEffect(transform.scale)
        .rotation3DEffect(
            .degrees(transform.rotationDegrees),
            axis: (x: 0, y: 1, z: 0),
            anchor: relativeIndex > 0 ? .leading : .trailing,
            perspective: reduceMotion ? 0 : 0.28
        )
        .opacity(transform.opacity)
        .offset(x: transform.horizontalOffset, y: transform.verticalOffset)
        .zIndex(relativeIndex == 0 ? 2 : 1)
        .allowsHitTesting(relativeIndex == 0 && !horizontalDragActive)
        .accessibilityHidden(relativeIndex != 0)
        .animation(settleAnimation, value: focusedID)
    }

    private func rackArrows(focusedIndex: Int) -> some View {
        HStack {
            if WeeklyMealCarouselLayout.canMoveBackward(from: focusedIndex) {
                rackArrow(
                    systemName: "chevron.left",
                    label: "Previous weekly meal",
                    direction: -1
                )
            } else {
                Color.clear.frame(width: 42, height: 42)
            }

            Spacer(minLength: 0)

            if WeeklyMealCarouselLayout.canMoveForward(from: focusedIndex, count: models.count) {
                rackArrow(
                    systemName: "chevron.right",
                    label: "Next weekly meal",
                    direction: 1
                )
            } else {
                Color.clear.frame(width: 42, height: 42)
            }
        }
        .padding(.horizontal, 10)
    }

    private func rackArrow(systemName: String, label: String, direction: Int) -> some View {
        Button {
            moveFocus(by: direction)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.46), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.30), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func rackDragGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !horizontalDragActive {
                    guard WeeklyMealCarouselLayout.isHorizontalDrag(value.translation) else { return }
                    horizontalDragActive = true
                }

                dragTranslation = WeeklyMealCarouselLayout.clampedDragTranslation(
                    value.translation.width,
                    focusedIndex: WeeklyMealCarouselLayout.focusedIndex(
                        focusedID: focusedID,
                        models: models
                    ),
                    count: models.count,
                    cardWidth: cardWidth
                )
            }
            .onEnded { value in
                guard horizontalDragActive else { return }
                horizontalDragActive = false

                let currentIndex = WeeklyMealCarouselLayout.focusedIndex(
                    focusedID: focusedID,
                    models: models
                )
                let targetIndex = WeeklyMealCarouselLayout.targetIndex(
                    currentIndex: currentIndex,
                    translation: value.translation.width,
                    predictedTranslation: value.predictedEndTranslation.width,
                    cardWidth: cardWidth,
                    count: models.count
                )

                userInteractionPendingFocus = targetIndex != currentIndex
                withAnimation(settleAnimation) {
                    focusedID = models[targetIndex].id
                    dragTranslation = 0
                }
            }
    }

    private var settleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.44, dampingFraction: 0.86, blendDuration: 0.08)
    }

    private func moveFocus(by direction: Int) {
        let currentIndex = WeeklyMealCarouselLayout.focusedIndex(
            focusedID: focusedID,
            models: models
        )
        let targetIndex = min(max(currentIndex + direction, 0), models.count - 1)
        guard targetIndex != currentIndex else { return }

        userInteractionPendingFocus = true
        withAnimation(settleAnimation) {
            focusedID = models[targetIndex].id
            dragTranslation = 0
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

    private func scheduleDwell(for id: CuratedRecipeID?) {
        dwellTask?.cancel()
        guard let id else { return }
        dwellTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled,
                  focusedID == id,
                  let model = models.first(where: { $0.id == id }) else { return }
            onFocused(model)
        }
    }
}

struct WeeklyMealRackTransform: Equatable {
    let horizontalOffset: CGFloat
    let verticalOffset: CGFloat
    let scale: CGFloat
    let opacity: CGFloat
    let rotationDegrees: Double
}

enum WeeklyMealCarouselLayout {
    static func cardWidth(containerWidth: CGFloat) -> CGFloat {
        containerWidth
    }

    static func focusedIndex(
        focusedID: CuratedRecipeID?,
        models: [WeeklyMealDisplayModel]
    ) -> Int {
        guard let focusedID,
              let index = models.firstIndex(where: { $0.id == focusedID }) else { return 0 }
        return index
    }

    static func isHorizontalDrag(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.12
    }

    static func clampedDragTranslation(
        _ translation: CGFloat,
        focusedIndex: Int,
        count: Int,
        cardWidth: CGFloat
    ) -> CGFloat {
        let movingPastFirst = focusedIndex == 0 && translation > 0
        let movingPastLast = focusedIndex == count - 1 && translation < 0
        let resistance: CGFloat = movingPastFirst || movingPastLast ? 0.16 : 1
        return min(max(translation * resistance, -cardWidth), cardWidth)
    }

    static func targetIndex(
        currentIndex: Int,
        translation: CGFloat,
        predictedTranslation: CGFloat,
        cardWidth: CGFloat,
        count: Int
    ) -> Int {
        let threshold = cardWidth * 0.22
        let intent = abs(predictedTranslation) > abs(translation) ? predictedTranslation : translation
        guard abs(intent) >= threshold else { return currentIndex }
        return min(max(currentIndex + (intent < 0 ? 1 : -1), 0), count - 1)
    }

    static func canMoveBackward(from index: Int) -> Bool {
        index > 0
    }

    static func canMoveForward(from index: Int, count: Int) -> Bool {
        index < count - 1
    }

    static func rackTransform(
        relativeIndex: Int,
        dragTranslation: CGFloat,
        cardWidth: CGFloat,
        reduceMotion: Bool
    ) -> WeeklyMealRackTransform {
        guard cardWidth > 0 else {
            return WeeklyMealRackTransform(
                horizontalOffset: 0,
                verticalOffset: 0,
                scale: 1,
                opacity: relativeIndex == 0 ? 1 : 0,
                rotationDegrees: 0
            )
        }

        let normalizedDrag = min(abs(dragTranslation) / cardWidth, 1)
        let horizontalOffset = CGFloat(relativeIndex) * cardWidth + dragTranslation

        if relativeIndex == 0 {
            return WeeklyMealRackTransform(
                horizontalOffset: dragTranslation * 0.92,
                verticalOffset: reduceMotion ? 0 : normalizedDrag * 3,
                scale: reduceMotion ? 1 : 1 - normalizedDrag * 0.025,
                opacity: 1,
                rotationDegrees: reduceMotion ? 0 : Double(dragTranslation / cardWidth) * 3.5
            )
        }

        let isIncoming = (relativeIndex > 0 && dragTranslation < 0)
            || (relativeIndex < 0 && dragTranslation > 0)
        let revealProgress = isIncoming ? normalizedDrag : 0

        return WeeklyMealRackTransform(
            horizontalOffset: horizontalOffset,
            verticalOffset: reduceMotion ? 0 : (1 - revealProgress) * 10,
            scale: reduceMotion ? 1 : 0.94 + revealProgress * 0.06,
            opacity: revealProgress,
            rotationDegrees: reduceMotion
                ? 0
                : Double(relativeIndex) * -6 * Double(1 - revealProgress)
        )
    }
}
