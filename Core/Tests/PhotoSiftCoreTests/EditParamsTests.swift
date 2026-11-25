import CoreGraphics
import Foundation
import Testing
@testable import PhotoSiftCore

@Suite("EditParamsTests")
struct EditParamsTests {
    @Test func identityForLandscapeImage() {
        let params = EditParams.identity(for: CGSize(width: 3936, height: 2624))
        #expect(params.orientation == .landscape)
        #expect(params.crop == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(params.angle == 0 && params.temperature == 0 && params.tint == 0 && params.exposure == 0)
        #expect(params.isIdentity)
    }

    @Test func identityForPortraitImage() {
        let params = EditParams.identity(for: CGSize(width: 400, height: 600))
        #expect(params.orientation == .portrait)
        #expect(params.isIdentity)
    }

    @Test func isIdentityFalseAfterAnyChange() {
        let base = EditParams.identity(for: CGSize(width: 600, height: 400))
        var cropped = base
        cropped.crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        var rotated = base
        rotated.angle = 1.5
        var warm = base
        warm.temperature = 10
        var tinted = base
        tinted.tint = -5
        var exposed = base
        exposed.exposure = 0.5
        for changed in [cropped, rotated, warm, tinted, exposed] {
            #expect(!changed.isIdentity)
        }
    }

    @Test func fingerprintIsStable() {
        let params = EditParams(
            crop: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25),
            orientation: .landscape,
            angle: 3.5,
            temperature: 20,
            tint: -10,
            exposure: 0.5
        )
        #expect(params.fingerprint == params.fingerprint)
        // Pinned value: guards against changes to the canonical form across runs/releases.
        #expect(params.fingerprint == "74e35bf6d43f61cf3edee5c2def82c94")
    }

    @Test func fingerprintDistinguishesEveryField() {
        let base = EditParams.identity(for: CGSize(width: 600, height: 400))
        var variants: [EditParams] = [base]
        var v = base; v.crop = CGRect(x: 0.1, y: 0, width: 0.9, height: 1); variants.append(v)
        v = base; v.orientation = .portrait; variants.append(v)
        v = base; v.angle = 0.1; variants.append(v)
        v = base; v.temperature = 1; variants.append(v)
        v = base; v.tint = 1; variants.append(v)
        v = base; v.exposure = 1; variants.append(v)
        #expect(Set(variants.map(\.fingerprint)).count == variants.count)
    }

    @Test func fingerprintTreatsNegativeZeroAsZero() {
        var a = EditParams.identity(for: CGSize(width: 600, height: 400))
        var b = a
        a.angle = 0
        b.angle = -0.0
        #expect(a.fingerprint == b.fingerprint)
    }

    @Test func codableRoundTrip() throws {
        let params = EditParams(
            crop: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25),
            orientation: .portrait,
            angle: -12.3,
            temperature: 45,
            tint: -7,
            exposure: -1.25
        )
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(EditParams.self, from: data)
        #expect(decoded == params)
        #expect(decoded.fingerprint == params.fingerprint)
    }
}
