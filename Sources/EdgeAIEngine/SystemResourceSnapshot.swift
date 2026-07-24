import Darwin
import Foundation

public struct SystemResourceSnapshot: Codable, Equatable {
    public let thermalState: String
    public let physicalMemoryBytes: UInt64
    public let residentMemoryBytes: UInt64?

    public init(
        thermalState: String,
        physicalMemoryBytes: UInt64,
        residentMemoryBytes: UInt64?
    ) {
        self.thermalState = thermalState
        self.physicalMemoryBytes = physicalMemoryBytes
        self.residentMemoryBytes = residentMemoryBytes
    }
}

public enum SystemResourceMonitor {
    public static func snapshot() -> SystemResourceSnapshot {
        SystemResourceSnapshot(
            thermalState: ProcessInfo.processInfo.thermalState.edgeAIDescription,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            residentMemoryBytes: residentMemoryBytes()
        )
    }

    private static func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return UInt64(info.resident_size)
    }
}

private extension ProcessInfo.ThermalState {
    var edgeAIDescription: String {
        switch self {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}
