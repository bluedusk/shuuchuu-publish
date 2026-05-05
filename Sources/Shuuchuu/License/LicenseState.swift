import Foundation

/// State machine for entitlement. `LicenseController` owns one of these and publishes it.
enum LicenseState: Equatable, Sendable {
    case uninitialized
    case trial(startedAt: Date)
    case trialExpired
    case licensed(key: String, instanceId: String, lastValidated: Date)
    case revoked(reason: RevokeReason)

    var isUnlocked: Bool {
        switch self {
        case .trial, .licensed: return true
        case .uninitialized, .trialExpired, .revoked: return false
        }
    }
}

enum RevokeReason: String, Equatable, Sendable, Codable {
    case disabled
    case expired
    case refunded
}
