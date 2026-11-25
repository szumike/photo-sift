import Foundation

/// A message for the UI: a headline and an optional second line.
public struct Toast: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let text: String
    public let subtext: String?

    public init(_ text: String, subtext: String? = nil) {
        self.text = text
        self.subtext = subtext
    }
}

/// Polish noun forms, e.g. 1 zdjęcie, 2 zdjęcia, 5 zdjęć.
public enum PolishPlural {
    public static func form(_ count: Int, one: String, few: String, many: String) -> String {
        if count == 1 { return one }
        let lastDigit = count % 10
        let lastTwo = count % 100
        if (2...4).contains(lastDigit) && !(12...14).contains(lastTwo) { return few }
        return many
    }

    public static func photos(_ count: Int) -> String {
        "\(count) " + form(count, one: "zdjęcie", few: "zdjęcia", many: "zdjęć")
    }

    public static func rawFiles(_ count: Int) -> String {
        "\(count) " + form(count, one: "plik RAW", few: "pliki RAW", many: "plików RAW")
    }

    /// "JPEG, ARW i XMP"
    public static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " i " + items[items.count - 1]
    }
}
