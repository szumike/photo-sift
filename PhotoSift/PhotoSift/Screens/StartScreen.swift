import PhotoSiftCore
import SwiftUI
import UniformTypeIdentifiers

/// Start screen: folder drop zone, "Otwórz folder…" and the recent folders list.
/// Identifiers: `screen.start`, `start.dropZone`, `start.openFolder`, `start.recent.<index>`.
struct StartScreen: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 28) {
            dropZone
            recents
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
        .background { Color.clear.accessibilityIdentifier("screen.start") }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 0x5a / 255, green: 0xa2 / 255, blue: 0xf5 / 255))
            Text(isTargeted ? "Upuść folder tutaj" : "Przeciągnij tu folder ze zdjęciami")
                .font(.system(size: 20, weight: .semibold))
            Text("Pliki JPG i ARW o tej samej nazwie pokażę jako jedno zdjęcie.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button { model.chooseFolder() } label: {
                HStack(spacing: 8) {
                    Text("Otwórz folder…")
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
            .padding(.top, 8)
            .accessibilityIdentifier("start.openFolder")
        }
        .frame(width: 640, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(isTargeted ? Palette.accent.opacity(0.12) : .white.opacity(0.04))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        model.openFolder(url)
                    }
                }
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("start.dropZone")
    }

    @ViewBuilder
    private var recents: some View {
        let folders = model.recentFoldersStore.folders()
        if !folders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("OSTATNIE FOLDERY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.leading, 12)
                VStack(spacing: 0) {
                    ForEach(Array(folders.enumerated()), id: \.element.path) { index, folder in
                        RecentRow(folder: folder) { model.openFolder(URL(fileURLWithPath: folder.path, isDirectory: true)) }
                            .accessibilityIdentifier("start.recent.\(index)")
                    }
                }
                .padding(6)
                .background(Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x28 / 255), in: RoundedRectangle(cornerRadius: 14))
            }
            .frame(width: 640)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("start.recents")
        }
    }
}

private struct RecentRow: View {
    let folder: RecentFolder
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0x4f / 255, green: 0x95 / 255, blue: 0xec / 255))
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name).font(.system(size: 13, weight: .semibold))
                    Text("\(folder.path) · \(PolishPlural.photos(folder.photoCount))")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(Self.dateText(folder.date))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func dateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
