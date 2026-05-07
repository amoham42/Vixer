import SwiftUI

struct SliderValueMapper {
    static func value(for locationX: CGFloat, width: CGFloat) -> Float {
        guard width > 0 else { return 0 }
        return Float(UnitInterval.clamp(locationX / width))
    }
}

struct SliderGeometry {
    static func thumbCenterX(for value: Float, width: CGFloat, thumbSize: CGFloat) -> CGFloat {
        guard width > 0, thumbSize > 0 else { return 0 }
        guard width > thumbSize else { return width / 2 }
        let clampedValue = CGFloat(UnitInterval.clamp(value))
        return max(thumbSize / 2, min(width - thumbSize / 2, clampedValue * width))
    }

    static func fillWidth(for value: Float, width: CGFloat, thumbSize: CGFloat) -> CGFloat {
        guard width > 0, thumbSize > 0 else { return 0 }
        let clampedValue = CGFloat(UnitInterval.clamp(value))
        guard clampedValue > 0 else { return 0 }
        return min(width, thumbCenterX(for: value, width: width, thumbSize: thumbSize) + thumbSize / 2)
    }

    static func percentageText(for value: Float) -> String {
        let clampedValue = UnitInterval.clamp(value)
        return "\(Int(clampedValue * 100))%"
    }
}

struct VolumeSliderView: View {
    @Binding var value: Float
    var isEnabled: Bool = true

    private let height: CGFloat = 22
    private let thumbSize: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumbX = SliderGeometry.thumbCenterX(for: value, width: width, thumbSize: thumbSize)
            let fillWidth = SliderGeometry.fillWidth(for: value, width: width, thumbSize: thumbSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(isEnabled ? 0.22 : 0.12))
                    .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)

                Capsule()
                    .fill(.white.opacity(isEnabled ? 0.96 : 0.36))
                    .frame(width: fillWidth)
                    .allowsHitTesting(false)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(isEnabled ? 0.28 : 0.12), radius: 3, x: 0, y: 1)
                    .position(x: thumbX, y: height / 2)
                    .allowsHitTesting(false)

                Text(SliderGeometry.percentageText(for: value))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.black.opacity(isEnabled ? 0.56 : 0.30))
                    .shadow(color: .white.opacity(isEnabled ? 0.18 : 0.08), radius: 0.5, x: 0, y: 0.5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1.0 : 0.55)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        value = SliderValueMapper.value(for: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(SliderGeometry.percentageText(for: value).replacing("%", with: " percent"))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment:
                value = UnitInterval.clamp(value + 0.05)
            case .decrement:
                value = UnitInterval.clamp(value - 0.05)
            @unknown default:
                break
            }
        }
    }
}
