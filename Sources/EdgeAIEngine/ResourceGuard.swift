import Foundation

public enum ResourceGuardError: Error, CustomStringConvertible {
    case inputTooLarge(bytes: Int, limit: Int)
    case thermalsCritical
    case residentMemoryTooHigh(bytes: UInt64, limit: UInt64)

    public var description: String {
        switch self {
        case .inputTooLarge(let bytes, let limit):
            return "Input is \(bytes) bytes, which exceeds the configured limit of \(limit) bytes."
        case .thermalsCritical:
            return "The system thermal state is critical. Workload should be deferred."
        case .residentMemoryTooHigh(let bytes, let limit):
            return "Resident memory is \(bytes) bytes, which exceeds the configured limit of \(limit) bytes."
        }
    }
}

public struct ResourceBudget: Equatable {
    public let maxInputBytes: Int
    public let maxChunksPerPrompt: Int
    public let reduceContextWhenThermalsElevated: Bool
    public let maxResidentMemoryBytes: UInt64?

    public init(
        maxInputBytes: Int = 50 * 1024 * 1024,
        maxChunksPerPrompt: Int = 6,
        reduceContextWhenThermalsElevated: Bool = true,
        maxResidentMemoryBytes: UInt64? = nil
    ) {
        self.maxInputBytes = maxInputBytes
        self.maxChunksPerPrompt = maxChunksPerPrompt
        self.reduceContextWhenThermalsElevated = reduceContextWhenThermalsElevated
        self.maxResidentMemoryBytes = maxResidentMemoryBytes
    }
}

public struct ResourceGuard {
    public let budget: ResourceBudget

    public init(budget: ResourceBudget = ResourceBudget()) {
        self.budget = budget
    }

    public func validateInputSize(_ bytes: Int) throws {
        guard bytes <= budget.maxInputBytes else {
            throw ResourceGuardError.inputTooLarge(bytes: bytes, limit: budget.maxInputBytes)
        }
    }

    public func validateThermals() throws {
        if ProcessInfo.processInfo.thermalState == .critical {
            throw ResourceGuardError.thermalsCritical
        }
    }

    public func validateResidentMemory() throws {
        guard let limit = budget.maxResidentMemoryBytes,
              let current = SystemResourceMonitor.snapshot().residentMemoryBytes,
              current > limit else {
            return
        }

        throw ResourceGuardError.residentMemoryTooHigh(bytes: current, limit: limit)
    }

    public func validateSystemForWorkload() throws {
        try validateThermals()
        try validateResidentMemory()
    }

    public func admittedTopK(requested: Int) -> Int {
        let clamped = min(max(1, requested), budget.maxChunksPerPrompt)

        guard budget.reduceContextWhenThermalsElevated else {
            return clamped
        }

        switch ProcessInfo.processInfo.thermalState {
        case .serious:
            return max(1, min(clamped, 2))
        case .critical:
            return 0
        default:
            return clamped
        }
    }
}
