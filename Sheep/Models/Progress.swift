import Foundation

/// XP = time well spent. Level = xp / 100. Wool has 5 visual stages (0…4).
/// The XP rules live in `XPRules` (step 7); this is just the stored value.
struct Progress: Codable, Equatable {
    var xp: Int = 0

    var level: Int { max(0, xp) / 100 }

    /// 0…4. Grows every 20 XP within a level so wool visibly changes during a demo,
    /// and a full fleece (stage 4) is shown at level ≥ 4.
    var woolStage: Int {
        if level >= 4 { return 4 }
        return min(4, (max(0, xp) % 100) / 20)
    }

    mutating func add(_ amount: Int) {
        xp = max(0, xp + amount)
    }
}
