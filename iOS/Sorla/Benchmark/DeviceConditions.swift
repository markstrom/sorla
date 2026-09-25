import Foundation
import Network
import os
import UIKit

// The build, device and conditions a measurement was taken under, recorded with every result.
struct DeviceConditions: Equatable, Sendable {
    static let fluidAudio = "FluidAudio 0.16.1 (b811a61569aa02691c99b808d08ee989b630c133)"
    static let encoderPrecision = "int8 encoder weights (per the model card)"

    var deviceModel: String
    var isSimulator: Bool
    var systemVersion: String
    var buildConfiguration: String
    var physicalMemory: UInt64
    var thermalState: String
    var batteryLevel: Float
    var batteryState: String
    var isLowPowerMode: Bool
    var isVoiceOverRunning: Bool
    var network: String
    var appVersion: String

    @MainActor
    static func capture(network: String) -> DeviceConditions {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let info = Bundle.main.infoDictionary ?? [:]
        return DeviceConditions(
            deviceModel: modelIdentifier(),
            isSimulator: isSimulator,
            systemVersion: "\(device.systemName) \(device.systemVersion)",
            buildConfiguration: buildConfiguration,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            thermalState: describe(ProcessInfo.processInfo.thermalState),
            batteryLevel: device.batteryLevel,
            batteryState: describe(device.batteryState),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            network: network,
            appVersion: "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        )
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    // "iPhone16,1" rather than a marketing name, so results can't be attributed to the wrong model.
    static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static func describe(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }

    var batteryDescription: String {
        batteryLevel < 0 ? "unknown" : "\(Int((batteryLevel * 100).rounded())) % \(batteryState)"
    }

    // Seconds since this process was started by the kernel, for cold-start figures.
    static func processUptime() -> TimeInterval? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        return Date().timeIntervalSince(started)
    }
}

// One reading of the network path, so results can show whether the phone was offline.
enum NetworkStatus {
    static func current() async -> String {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let answered = OSAllocatedUnfairLock(initialState: false)
            monitor.pathUpdateHandler = { path in
                let isFirst = answered.withLock { answered in
                    defer { answered = true }
                    return !answered
                }
                guard isFirst else { return }
                monitor.cancel()
                continuation.resume(returning: describe(path))
            }
            monitor.start(queue: DispatchQueue(label: "com.sorla.ios.network-status"))
        }
    }

    private static func describe(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "offline" }
        if path.usesInterfaceType(.wifi) { return "online (Wi-Fi)" }
        if path.usesInterfaceType(.cellular) { return "online (cellular)" }
        return "online"
    }
}
