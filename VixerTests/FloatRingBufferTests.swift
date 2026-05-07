import Testing
@testable import Vixer

struct FloatRingBufferTests {
    @Test func readReturnsZerosWhenEmpty() {
        let buffer = FloatRingBuffer(capacity: 4)
        var output = [Float](repeating: -1, count: 3)

        buffer.read(into: &output, count: output.count)

        #expect(output == [0, 0, 0])
    }

    @Test func writeThenReadReturnsSamplesInOrder() {
        let buffer = FloatRingBuffer(capacity: 8)
        buffer.write([1, 2, 3, 4], count: 4)
        var output = [Float](repeating: 0, count: 4)

        buffer.read(into: &output, count: output.count)

        #expect(output == [1, 2, 3, 4])
    }

    @Test func writeDropsOldestSamplesWhenCapacityIsExceeded() {
        let buffer = FloatRingBuffer(capacity: 4)
        buffer.write([1, 2, 3, 4, 5, 6], count: 6)
        var output = [Float](repeating: 0, count: 4)

        buffer.read(into: &output, count: output.count)

        #expect(output == [3, 4, 5, 6])
    }
}
