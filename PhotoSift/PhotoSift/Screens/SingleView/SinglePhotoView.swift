import PhotoSiftCore
import SwiftUI

/// The single-photo screen: the stage (photo or edit stage), the filmstrip and the info panel.
/// Identifiers: `screen.single`; the parts add their own.
struct SinglePhotoView: View {
    let session: Session
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                PhotoStage(session: session, albumStatuses: session.exportStatuses)
                Filmstrip(session: session, albumStatuses: session.exportStatuses)
            }
            .padding(8)
            InfoPanel(session: session, albumStatus: session.currentID.flatMap { session.exportStatuses[$0] })
                .frame(width: 300)
        }
        .background { Color.clear.accessibilityIdentifier("screen.single") }
        .task(id: session.currentID) { await prefetchNeighbours() }
    }

    /// Warms the previews of the two photos on each side of the current one.
    private func prefetchNeighbours() async {
        let visible = session.visiblePhotos
        guard let id = session.currentID, let index = visible.firstIndex(where: { $0.id == id }) else { return }
        let range = max(0, index - 2)...min(visible.count - 1, index + 2)
        let ids = range.filter { $0 != index }.map { visible[$0].id }
        await model.loader.prefetch(ids: ids)
    }
}
