import Foundation
import EdgeAINativeKernels

public enum LocalRuntimeKind: String, Codable, CaseIterable {
    case extractive
    case llamaCppServer = "llama.cpp-server"
    case nativeLlamaCpp = "native-llama.cpp"
    case mlxSwift = "mlx-swift"
}

public struct LocalRuntimeStatus: Codable, Equatable {
    public let kind: LocalRuntimeKind
    public let available: Bool
    public let detail: String

    public init(kind: LocalRuntimeKind, available: Bool, detail: String) {
        self.kind = kind
        self.available = available
        self.detail = detail
    }
}

public enum LocalRuntimeRegistry {
    public static func statuses() -> [LocalRuntimeStatus] {
        [
            extractiveStatus(),
            llamaCppServerStatus(),
            nativeLlamaCppStatus(),
            mlxSwiftStatus()
        ]
    }

    public static func status(for kind: LocalRuntimeKind) -> LocalRuntimeStatus {
        switch kind {
        case .extractive:
            return extractiveStatus()
        case .llamaCppServer:
            return llamaCppServerStatus()
        case .nativeLlamaCpp:
            return nativeLlamaCppStatus()
        case .mlxSwift:
            return mlxSwiftStatus()
        }
    }

    private static func extractiveStatus() -> LocalRuntimeStatus {
        LocalRuntimeStatus(
            kind: .extractive,
            available: true,
            detail: "Built-in deterministic local fallback."
        )
    }

    private static func llamaCppServerStatus() -> LocalRuntimeStatus {
        LocalRuntimeStatus(
            kind: .llamaCppServer,
            available: true,
            detail: "Supported through a user-provided local llama-server URL."
        )
    }

    private static func nativeLlamaCppStatus() -> LocalRuntimeStatus {
        let available = edgeai_llamacpp_headers_available() != 0
        let mode = String(cString: edgeai_llamacpp_integration_mode())
        return LocalRuntimeStatus(
            kind: .nativeLlamaCpp,
            available: available,
            detail: available
                ? "Native llama.cpp C API headers were visible at build time; integration mode=\(mode)."
                : "Native llama.cpp headers were not visible at build time; use llama.cpp server mode for local generation."
        )
    }

    private static func mlxSwiftStatus() -> LocalRuntimeStatus {
        #if canImport(MLX)
        return LocalRuntimeStatus(
            kind: .mlxSwift,
            available: true,
            detail: "MLX Swift module is visible to the build."
        )
        #else
        return LocalRuntimeStatus(
            kind: .mlxSwift,
            available: false,
            detail: "MLX Swift module is not linked into this build."
        )
        #endif
    }
}
