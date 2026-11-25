import PhotoSiftCore
import SwiftUI

/// Replaces the edit controls for a photo that cannot be edited.
/// Identifiers: `edit.locked.title`, `edit.locked.text`, `edit.locked.unmark`.
struct LockedEditPanel: View {
    let session: Session
    let item: PhotoItem

    var body: some View {
        let isRawOnlyLock = item.isRawOnly && !session.isSent(item) && !session.isMarked(item)
        let inDarkroom = session.isSent(item) || session.isMarked(item)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text(isRawOnlyLock ? "Edycja niedostępna" : "Edycja zablokowana")
                    .accessibilityIdentifier("edit.locked.title")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.amber)
            Text(inDarkroom
                ? (session.isInPhotos(item)
                    ? "RAW jest w Zdjęciach — obrobisz go stamtąd."
                    : "Zdjęcie jest w Ciemni — obrobisz je w Lightroomie z pliku RAW.")
                : "Brak JPEG-a. Photo Sift edytuje tylko JPEG-i.")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("edit.locked.text")
            if !session.isSent(item) && session.isMarked(item) {
                Button {
                    session.toggleDarkroom()
                } label: {
                    HStack(spacing: 8) {
                        Text("Usuń oznaczenie Ciemni")
                        Text("C").foregroundStyle(Palette.secondaryText)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("edit.locked.unmark")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
