import SwiftUI

/// The look of a slider track, as in the prototype (`.rng`, `.r-temp`, `.r-tint`, `.r-exp`).
enum SliderTrack {
    case plain, temperature, tint, exposure

    fileprivate var fill: AnyShapeStyle {
        switch self {
        case .plain: AnyShapeStyle(.white.opacity(0.2))
        case .temperature: Self.gradient(0x3d7dff, 0xffae2e)
        case .tint: Self.gradient(0x2fcf68, 0xe046c8)
        case .exposure: Self.gradient(0x111111, 0xffffff)
        }
    }

    private static func gradient(_ low: UInt32, _ high: UInt32) -> AnyShapeStyle {
        AnyShapeStyle(LinearGradient(
            stops: [
                .init(color: Color(hex: low), location: 0),
                .init(color: Color(hex: 0xcfcfcf), location: 0.5),
                .init(color: Color(hex: high), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        ))
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

/// A slider with a 4 pt track and an 18 pt round thumb. Dragging anywhere on the track sets the value
/// (snapped to `step`); `onEditingChanged(true)` fires when a drag starts and `(false)` when it ends.
/// For accessibility it is a real slider, so it is adjustable by keyboard, VoiceOver and XCUITest.
struct RangeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let track: SliderTrack
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false
    @FocusState private var isFocused: Bool

    private static let thumb: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - Self.thumb, 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(track.fill)
                    .frame(height: 4)
                Circle()
                    .fill(Color(red: 0xec / 255, green: 0xec / 255, blue: 0xee / 255))
                    .frame(width: Self.thumb, height: Self.thumb)
                    .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
                    .overlay {
                        if isFocused {
                            Circle().stroke(Palette.accent.opacity(0.7), lineWidth: 3)
                        }
                    }
                    .offset(x: fraction * travel)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let position = (drag.location.x - Self.thumb / 2) / travel
                        value = snapped(range.lowerBound + position * (range.upperBound - range.lowerBound))
                    }
                    .onEnded { _ in finishDrag() }
            )
            .onDisappear { finishDrag() }
        }
        .frame(height: Self.thumb)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { nudge(-1) }
        .onKeyPress(.downArrow) { nudge(-1) }
        .onKeyPress(.rightArrow) { nudge(1) }
        .onKeyPress(.upArrow) { nudge(1) }
        .accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: { value = snapped($0) }), in: range, step: step)
        }
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
    }

    private func snapped(_ raw: Double) -> Double {
        min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
    }

    private func nudge(_ direction: Double) -> KeyPress.Result {
        value = snapped(value + direction * step)
        return .handled
    }

    private func finishDrag() {
        guard isDragging else { return }
        isDragging = false
        onEditingChanged(false)
    }
}
