import CoreAudio
import Foundation
import OSLog

final class TapOutputRenderer {
    private static let log = Logger(subsystem: "app.vixer.Vixer", category: "TapRenderer")

    private let ringBuffer: FloatRingBuffer
    private let channelCount: Int
    private let sampleRate: Double
    private var outputDeviceID: AudioObjectID
    private var ioProcID: AudioDeviceIOProcID?
    private var ioProcLogged = false

    init(sampleRate: Double, channelCount: UInt32, bufferedSeconds: Double = 0.5) throws {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        self.channelCount = max(1, Int(channelCount))
        let capacity = max(Int(self.sampleRate * bufferedSeconds) * self.channelCount, 1024)
        self.ringBuffer = FloatRingBuffer(capacity: capacity)
        self.outputDeviceID = MasterVolumeService.defaultOutputDeviceID()
        try installIOProc()
    }

    deinit { stop() }

    func writeInterleaved(_ samples: UnsafePointer<Float>, sampleCount: Int) {
        guard sampleCount > 0 else { return }
        ringBuffer.write(samples, count: sampleCount)
    }

    func start() throws {
        guard let ioProcID else { return }
        let status = AudioDeviceStart(outputDeviceID, ioProcID)
        guard status == noErr else {
            throw AudioTapError.rendererStartFailed(status: status)
        }
        Self.log.info("Started CoreAudio tap renderer deviceID=\(self.outputDeviceID, privacy: .public) sr=\(self.sampleRate, privacy: .public) ch=\(self.channelCount, privacy: .public)")
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(outputDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(outputDeviceID, ioProcID)
            self.ioProcID = nil
        }
    }

    private func installIOProc() throws {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &procID,
            outputDeviceID,
            nil
        ) { [weak self] _, _, _, outOutputData, _ in
            guard let self else { return }
            let outABL = UnsafeMutableAudioBufferListPointer(outOutputData)
            if !self.ioProcLogged {
                self.ioProcLogged = true
                let buffers = outABL.count
                DispatchQueue.global(qos: .utility).async {
                    Self.log.info("Renderer IOProc fired buffers=\(buffers, privacy: .public)")
                }
            }

            for i in 0..<outABL.count {
                guard let outData = outABL[i].mData else { continue }
                let samples = Int(outABL[i].mDataByteSize) / MemoryLayout<Float>.size
                let outP = outData.assumingMemoryBound(to: Float.self)
                self.ringBuffer.read(into: outP, count: samples)
            }
        }
        guard status == noErr, let procID else {
            throw AudioTapError.rendererCreationFailed(status: status)
        }
        ioProcID = procID
    }
}
