import PhotoSiftCore
import SwiftUI

/// "Do Ciemni": confirms moving the marked photos' ARW (+ XMP) to `Ciemnia/`, or importing the ARW into Photos
/// (the target is a setting).
/// Enter confirms, Esc cancels. Identifiers: `sheet.darkroom`, `sheet.darkroom.text`, `sheet.darkroom.files`,
/// `sheet.darkroom.note`, `sheet.darkroom.progress`, `sheet.darkroom.cancel`, `sheet.darkroom.confirm`.
struct DarkroomSheet: View {
    let session: Session
    @Environment(AppModel.self) private var model

    private var target: DarkroomTarget { model.darkroomTarget }
    private var albumTitle: String { session.folder.lastPathComponent }

    private var items: [PhotoItem] {
        session.photos.filter { session.isMarked($0) && !session.isSent($0) && $0.rawURL != nil }
    }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.amber)
                    .frame(width: 40, height: 40)
                    .background(Palette.amber.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Do Ciemni").font(.system(size: 15, weight: .semibold))
                    Text(descriptionText(count: items.count))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sheet.darkroom.text")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        let name = item.rawURL?.lastPathComponent ?? item.id
                        Text(target == .photos ? "\(name) → Zdjęcia: \(albumTitle)" : "\(name) + .xmp → Ciemnia/")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.secondaryText)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: 140)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("sheet.darkroom.files")
            Text(target == .photos
                ? "Te zdjęcia nie trafią do eksportu z Photo Sift — obrobisz je w aplikacji Zdjęcia."
                : "Te zdjęcia nie trafią do eksportu z Photo Sift — gotowe pliki wyeksportujesz do Album/ z Lightrooma.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sheet.darkroom.note")
            HStack {
                if session.isSendingToDarkroom {
                    ProgressView().controlSize(.small)
                    Text("Dodawanie do Zdjęć…")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText)
                        .accessibilityIdentifier("sheet.darkroom.progress")
                }
                Spacer()
                Button("Anuluj") { model.sheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .disabled(session.isSendingToDarkroom)
                    .accessibilityIdentifier("sheet.darkroom.cancel")
                Button(target == .photos ? "Dodaj do Zdjęć" : "Przenieś RAW-y") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.primary)
                    .disabled(session.isSendingToDarkroom)
                    .accessibilityIdentifier("sheet.darkroom.confirm")
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Palette.toolbar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.darkroom")
    }

    private func descriptionText(count: Int) -> String {
        switch target {
        case .folder:
            "\(PolishPlural.rawFiles(count)) zostanie przeniesionych do Ciemnia/ (razem z plikami XMP). Pliki JPEG zostają na miejscu."
        case .photos:
            "\(PolishPlural.rawFiles(count)) zostanie dodanych do albumu „\(albumTitle)” w Zdjęciach. Pliki w folderze zostają bez zmian."
        }
    }

    /// The sheet stays open (with a progress indicator) until the send finishes.
    private func confirm() {
        let target = target
        Task {
            await session.sendToDarkroom(target: target)
            model.sheet = nil
        }
    }
}
