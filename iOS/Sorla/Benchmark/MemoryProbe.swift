import Darwin
import Foundation
import os

// phys_footprint is the number iOS compares against the app's memory limit, so all memory figures use it.
enum MemoryProbe {
    static func footprint() -> UInt64 {
        vmInfo()?.phys_footprint ?? 0
    }

    // Includes clean, file-backed pages such as memory-mapped model weights, which phys_footprint leaves out.
    static func resident() -> UInt64 {
        vmInfo()?.resident_size ?? 0
    }

    // The kernel's own high-water mark for this process's lifetime; it can't be reset.
    static func lifetimePeak() -> UInt64 {
        UInt64(max(0, vmInfo()?.ledger_phys_footprint_peak ?? 0))
    }

    // Headroom before the system terminates the app; 0 where no limit applies, such as the simulator.
    static func available() -> UInt64 {
        UInt64(os_proc_available_memory())
    }

    private static func vmInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}

// Polls the footprint on its own queue so a peak during a Core ML call isn't missed between two readings.
final class MemorySampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sorla.ios.memory-sampler", qos: .userInitiated)
    private let lock = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private var timer: DispatchSourceTimer?

    func start(interval: DispatchTimeInterval = .milliseconds(5)) {
        lock.withLock { $0 = MemoryProbe.footprint() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [lock] in
            let current = MemoryProbe.footprint()
            lock.withLock { $0 = max($0, current) }
        }
        self.timer = timer
        timer.resume()
    }

    // Returns the highest footprint seen since start, including one final reading.
    func stop() -> UInt64 {
        timer?.cancel()
        timer = nil
        let current = MemoryProbe.footprint()
        return lock.withLock { max($0, current) }
    }
}

enum DirectorySize {
    struct Size: Equatable, Sendable {
        var logical: Int64
        var allocated: Int64
    }

    static func of(_ url: URL) -> Size {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return Size(logical: 0, allocated: 0)
        }
        var size = Size(logical: 0, allocated: 0)
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            size.logical += Int64(values.fileSize ?? 0)
            size.allocated += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return size
    }
}

enum ByteFormat {
    // Decimal megabytes throughout, matching the manifest's byte counts.
    static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.0f", Double(bytes) / 1_000_000)
    }

    static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.0f", Double(bytes) / 1_000_000)
    }
}
