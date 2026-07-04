import CoreGraphics
import XCTest
@testable import WWIIHexV0

final class HexLayoutTests: XCTestCase {
    func testHexToPixelAndPixelToHexAreInverseAtCenters() {
        let layout = HexLayout(hexSize: 24, origin: CGPoint(x: 120, y: 80))
        let coords = [
            HexCoord(q: 0, r: 0),
            HexCoord(q: 1, r: 0),
            HexCoord(q: 0, r: 1),
            HexCoord(q: 4, r: 3),
            HexCoord(q: 10, r: 8)
        ]

        for coord in coords {
            let point = layout.hexToPixel(coord)
            XCTAssertEqual(layout.pixelToHex(point), coord)
        }
    }

    func testPointNearHexCenterReturnsExpectedCoord() {
        let layout = HexLayout(hexSize: 30, origin: CGPoint(x: 50, y: 50))
        let coord = HexCoord(q: 5, r: 4)
        let center = layout.hexToPixel(coord)
        let tapPoint = CGPoint(x: center.x + 4, y: center.y - 3)

        XCTAssertEqual(layout.pixelToHex(tapPoint), coord)
    }

    func testPolygonContainsSixPoints() {
        let layout = HexLayout(hexSize: 18, origin: .zero)
        let points = layout.polygonPoints(center: CGPoint(x: 10, y: 10))

        XCTAssertEqual(points.count, 6)
    }
}
