import PhotoSiftCore
import SwiftUI

/// A message bubble as in the prototype: a headline and an optional second line.
struct ToastView: View {
    let toast: Toast

    var body: some View {
        VStack(spacing: 2) {
            Text(toast.text)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityIdentifier("toast.text")
            if let subtext = toast.subtext {
                Text(subtext)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .accessibilityIdentifier("toast.subtext")
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
        .background(Color(red: 36 / 255, green: 36 / 255, blue: 38 / 255, opacity: 0.95), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}
