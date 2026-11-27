import SwiftUI

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model: AppModel
    private let launchArguments: LaunchArguments

    init() {
        let launchArguments = LaunchArguments()
        self.launchArguments = launchArguments
        _model = State(initialValue: AppModel(defaults: launchArguments.defaults))
    }

    var body: some Scene {
        // One window: Photo Sift shows one folder at a time, and a photo opened from Finder replaces it.
        Window("Photo Sift", id: "main") {
            MainWindow()
                .environment(model)
                .environment(model.viewState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1240, minHeight: 640)
                .onAppear {
                    model.start(opening: launchArguments.openFolderURL)
                    appDelegate.attach(model)
                }
        }
        .defaultSize(width: 1400, height: 880)
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
