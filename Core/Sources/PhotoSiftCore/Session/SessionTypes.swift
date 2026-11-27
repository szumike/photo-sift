import Foundation

public enum ViewMode: Sendable, Equatable { case single, grid }
public enum InteractionMode: Sendable, Equatable { case browse, edit }
public enum EditTool: Sendable, Equatable { case color, crop }
public enum PhotoFilter: Sendable, Equatable { case all, darkroom, edited, deletion }

public struct SelectionModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = SelectionModifiers(rawValue: 1 << 0)
    public static let shift = SelectionModifiers(rawValue: 1 << 1)
}

/// Copied white balance, in slider units (-100...100).
public struct WhiteBalanceClipboard: Sendable, Equatable {
    public var temperature: Double
    public var tint: Double

    public init(temperature: Double, tint: Double) {
        self.temperature = temperature
        self.tint = tint
    }
}
