import SwiftUI

/// Shown when the opened folder has no JPG or ARW files.
/// Identifiers: `screen.emptyFolder`, `emptyFolder.openOther`.
struct EmptyFolderScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.5))
            Text("Ten folder nie zawiera zdjęć")
                .font(.system(size: 20, weight: .semibold))
            Text("Photo Sift pokazuje tylko pliki JPG i ARW. Inne pliki są pomijane.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button { model.chooseFolder() } label: {
                HStack(spacing: 8) {
                    Text("Otwórz inny folder…")
                    Text("⌘O")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(Palette.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("emptyFolder.openOther")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.stage)
        .background { Color.clear.accessibilityIdentifier("screen.emptyFolder") }
    }
}
