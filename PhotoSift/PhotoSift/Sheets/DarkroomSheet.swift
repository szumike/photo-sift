import PhotoSiftCore
import SwiftUI

/// "Do Ciemni": confirms moving the marked photos' ARW (+ XMP) to `Ciemnia/`.
/// Enter confirms, Esc cancels. Identifiers: `sheet.darkroom`, `sheet.darkroom.text`, `sheet.darkroom.files`,
/// `sheet.darkroom.note`, `sheet.darkroom.cancel`, `sheet.darkroom.confirm`.
struct DarkroomSheet: View {
    let session: Session
    @Environment(AppModel.self) private var model

    private var items: [PhotoItem] {
        session.photos.filter { session.isMarked($0) && !$0.isSentToDarkroom && $0.rawURL != nil }
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
                    Text("\(PolishPlural.rawFiles(items.count)) zostanie przeniesionych do Ciemnia/ (razem z plikami XMP). Pliki JPEG zostają na miejscu.")
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
                        Text("\(name) + .xmp → Ciemnia/")
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
            Text("Te zdjęcia nie trafią do eksportu z Photo Sift — gotowe pliki wyeksportujesz do Album/ z Lightrooma.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sheet.darkroom.note")
            HStack {
                Spacer()
                Button("Anuluj") { model.sheet = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("sheet.darkroom.cancel")
                Button("Przenieś RAW-y") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.primary)
                    .accessibilityIdentifier("sheet.darkroom.confirm")
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Palette.toolbar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet.darkroom")
    }

    private func confirm() {
        model.sheet = nil
        Task { await session.sendToDarkroom() }
    }
}
