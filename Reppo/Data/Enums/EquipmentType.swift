import Foundation

enum EquipmentType: String, Codable, CaseIterable {
    case barbell
    case dumbbell
    case machinePlate
    case machinePin
    case bodyweight
    case sled
    case cable
    case kettlebell
    case band
    case other

    var displayName: String {
        switch self {
        case .barbell:     return "Barbell"
        case .dumbbell:    return "Dumbbell"
        case .machinePlate: return "Machine (Plate)"
        case .machinePin:  return "Machine (Pin)"
        case .bodyweight:  return "Bodyweight"
        case .sled:        return "Sled"
        case .cable:       return "Cable"
        case .kettlebell:  return "Kettlebell"
        case .band:        return "Band"
        case .other:       return "Other"
        }
    }
}
