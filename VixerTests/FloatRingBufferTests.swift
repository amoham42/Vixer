import XCTest
@testable import Vixer

final class FloatRingBufferTests: XCTestCase {
    func test_read_returnsZerosWhenEmpty() {
        let buffer = FloatRingBuffer(capacity: 4)
        var output = [Float](repeating: -1, count: 3)

        buffer.read(into: &output, count: output.count)

        XCTAssertEqual(output, [0, 0, 0])
    }

    func test_writeThenRead_returnsSamplesInOrder() {
        let buffer = FloatRingBuffer(capacity: 8)
        buffer.write([1, 2, 3, 4], count: 4)
        var output = [Float](repeating: 0, count: 4)

        buffer.read(into: &output, count: output.count)

        XCTAssertEqual(output, [1, 2, 3, 4])
    }

    func test_writeDropsOldestSamplesWhenCapacityIsExceeded() {
        let buffer = FloatRingBuffer(capacity: 4)
        buffer.write([1, 2, 3, 4, 5, 6], count: 6)
        var output = [Float](repeating: 0, count: 4)

        buffer.read(into: &output, count: output.count)

        XCTAssertEqual(output, [3, 4, 5, 6])
    }
}
