import SwiftUI

/// The Settings window (⌘,): the zoom level used when holding Z or the mouse on the photo.
/// Identifiers: `settings.zoomLevel`, `settings.zoomLevel.<percent>` per option.
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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
