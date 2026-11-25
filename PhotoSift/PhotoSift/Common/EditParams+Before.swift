import PhotoSiftCore

extension EditParams {
    /// The "Przed / po" view: temperature, tint and exposure off; crop and straightening stay applied.
    var withoutLightAndColor: EditParams {
        var copy = self
        copy.temperature = 0
        copy.tint = 0
        copy.exposure = 0
        return copy
    }
}
