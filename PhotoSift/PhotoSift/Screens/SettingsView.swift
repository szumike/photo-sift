import PhotoSiftCore
import SwiftUI

/// The Settings window (⌘,): the zoom level used when holding Z or the mouse on the photo.
/// Identifiers: `settings.zoomLevel`, `settings.zoomLevel.<percent>` per option, `settings.darkroomTarget`,
/// `settings.darkroomTarget.folder|photos`.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Powiększenie zoomu", selection: $model.zoomLevel) {
                ForEach(AppModel.zoomLevels, id: \.self) { level in
                    Text("\(Int((level * 100).rounded()))%")
                        .tag(level)
                        .accessibilityIdentifier("settings.zoomLevel.\(Int((level * 100).rounded()))")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.zoomLevel")
            Picker("Cel „Do Ciemni”", selection: $model.darkroomTarget) {
                Text("Folder Ciemnia/")
                    .tag(DarkroomTarget.folder)
                    .accessibilityIdentifier("settings.darkroomTarget.folder")
                Text("Zdjęcia (Photos)")
                    .tag(DarkroomTarget.photos)
                    .accessibilityIdentifier("settings.darkroomTarget.photos")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.darkroomTarget")
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
