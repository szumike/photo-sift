import Testing
import PhotoSiftCore
import PhotoSiftTestSupport

@Suite struct SmokeTests {
    @Test func packageLinks() {
        #expect(PhotoSiftCore.name == "PhotoSiftCore")
        #expect(PhotoSiftTestSupport.coreName == "PhotoSiftCore")
    }
}
