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
        .task(id: session.currentID) { await model.prefetchNeighbours(of: session) }
    }
}

/// F mode: only the current photo on black, full window. ← → move between photos (`KeyboardRouter`).
/// Identifier: `screen.presentation`.
struct PresentationView: View {
    let session: Session
    @Environment(AppModel.self) private var model

    var body: some View {
        PhotoStage(session: session, albumStatuses: session.exportStatuses, isPresentation: true)
            .ignoresSafeArea()
            .background { Color.clear.accessibilityIdentifier("screen.presentation") }
            .task(id: session.currentID) { await model.prefetchNeighbours(of: session) }
    }
}
