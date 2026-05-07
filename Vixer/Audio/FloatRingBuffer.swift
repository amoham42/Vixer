import Foundation

final class FloatRingBuffer {
    private var storage: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private var available = 0
    private let lock = NSLock()

    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = [Float](repeating: 0, count: self.capacity)
    }

    func write(_ samples: [Float], count requestedCount: Int) {
        samples.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            write(base, count: min(requestedCount, pointer.count))
        }
    }

    func write(_ samples: UnsafePointer<Float>, count requestedCount: Int) {
        let count = max(0, requestedCount)
        guard count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        let samplesToWrite = min(count, capacity)
        let startOffset = count - samplesToWrite
        if count >= capacity {
            readIndex = 0
            writeIndex = 0
            available = 0
        }

        for i in 0..<samplesToWrite {
            if available == capacity {
                readIndex = (readIndex + 1) % capacity
                available -= 1
            }
            storage[writeIndex] = samples[startOffset + i]
            writeIndex = (writeIndex + 1) % capacity
            available += 1
        }
    }

    func read(into output: inout [Float], count requestedCount: Int) {
        output.withUnsafeMutableBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            read(into: base, count: min(requestedCount, pointer.count))
        }
    }

    func read(into output: UnsafeMutablePointer<Float>, count requestedCount: Int) {
        let count = max(0, requestedCount)
        guard count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        for i in 0..<count {
            if available > 0 {
                output[i] = storage[readIndex]
                readIndex = (readIndex + 1) % capacity
                available -= 1
            } else {
                output[i] = 0
            }
        }
    }
}
