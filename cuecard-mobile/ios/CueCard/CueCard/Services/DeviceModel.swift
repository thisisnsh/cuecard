import Foundation

/// Hardware this iPhone has that the system gives no way to ask about, told
/// from its model identifier.
enum DeviceModel {
    /// "iPhone15,2" and the like. The simulator reports the Mac's architecture,
    /// and the simulated device separately.
    static let identifier: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    /// "iPhone15,2" is generation 15. iPads and anything else give nil.
    private static let iPhoneGeneration: Int? = {
        guard identifier.hasPrefix("iPhone") else { return nil }
        return Int(identifier.dropFirst("iPhone".count).prefix { $0.isNumber })
    }()

    /// Every iPhone from hardware generation 15 has the island: the 14 Pro is
    /// `iPhone15,2`, while the plain 14 is still `iPhone14,7`. Later models are
    /// assumed to have it too, except the 16e and 17e, which have a notch.
    static let hasDynamicIsland = hasDynamicIsland(identifier: identifier)

    static func hasDynamicIsland(identifier: String) -> Bool {
        guard identifier.hasPrefix("iPhone"),
              let generation = Int(identifier.dropFirst("iPhone".count).prefix { $0.isNumber }),
              identifier != "iPhone17,5", /* 16e */
              identifier != "iPhone18,5" /* 17e */ else { return false }
        return generation >= 15
    }

    /// The 15 Pro, `iPhone16,1`, was the first with the Action button, and
    /// every iPhone since has one, the 16e included. The plain 15 is still
    /// `iPhone15,4`.
    static let hasActionButton: Bool = {
        guard let generation = iPhoneGeneration else { return false }
        return generation >= 16
    }()
}
