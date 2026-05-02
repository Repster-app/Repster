import Foundation

enum E1RMFormula: String, CaseIterable, Sendable {
    case epley
    case brzycki
    case lombardi

    var displayName: String {
        switch self {
        case .epley:    return "Epley"
        case .brzycki:  return "Brzycki"
        case .lombardi: return "Lombardi"
        }
    }

    var description: String {
        switch self {
        case .epley:
            return "Most widely used. Works well across rep ranges. "
                 + "Formula: weight × (1 + reps / 30)"
        case .brzycki:
            return "Slightly more conservative at higher reps. "
                 + "Formula: weight × 36 / (37 − reps)"
        case .lombardi:
            return "Power-law model. Simple and predictable. "
                 + "Formula: weight × reps^0.10"
        }
    }

    func calculate(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        let r = Double(reps)
        switch self {
        case .epley:
            return weight * (1.0 + r / 30.0)
        case .brzycki:
            return weight * 36.0 / (37.0 - r)
        case .lombardi:
            return weight * pow(r, 0.10)
        }
    }

    /// Reverse-calculates estimated weight for a given rep count from an e1RM value.
    /// For reps <= 1, returns the e1RM unchanged (1RM = e1RM by definition).
    func reverseCalculate(e1RM: Double, reps: Int) -> Double {
        guard reps > 1 else { return e1RM }
        let r = Double(reps)
        switch self {
        case .epley:
            return e1RM / (1.0 + r / 30.0)
        case .brzycki:
            return e1RM * (37.0 - r) / 36.0
        case .lombardi:
            return e1RM / pow(r, 0.10)
        }
    }
}
