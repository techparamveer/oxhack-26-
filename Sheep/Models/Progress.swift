import Foundation

/// XP = time well spent. Level = xp / 100. Wool has 5 visual stages (0…4).
/// The XP rules live in `XPRules` (step 7); this is just the stored value.
struct Progress: Codable, Equatable {
    var xp: Int = 0

    var level: Int { max(0, xp) / 100 }

    /// XP needed for wool stages 1…4. Front-loaded so one demo session visibly grows wool
    /// (ticking 3 checklist items reaches stage 1), and monotonic so losing XP never grows wool.
    static let woolThresholds = [50, 150, 300, 500]

    /// 0…4, never decreases as xp increases.
    var woolStage: Int {
        Self.woolThresholds.filter { max(0, xp) >= $0 }.count
    }

    mutating func add(_ amount: Int) {
        xp = max(0, xp + amount)
    }
}
