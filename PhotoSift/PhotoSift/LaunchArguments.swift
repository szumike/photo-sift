import Foundation

struct LaunchArguments {
    let openFolderPath: String?
    /// `--defaults-suite <name>`: keep recents and resume positions in this `UserDefaults` suite (UI tests).
    let defaultsSuite: String?

    var defaults: UserDefaults {
        defaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    var openFolderURL: URL? {
        openFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    init(_ arguments: [String] = CommandLine.arguments) {
        openFolderPath = Self.value(of: "--open-folder", in: arguments)
        defaultsSuite = Self.value(of: "--defaults-suite", in: arguments)
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
