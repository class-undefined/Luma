import Foundation

public struct PhotoRating: Equatable, Sendable {
    public let value: Int
    public init(_ value: Int) { self.value = min(9, max(0, value)) }
    public var title: String { value == 0 ? "未评分" : "\(value) 级" }
}

public enum RatingFilter: Equatable, Sendable {
    case all, exact(Int), atLeast(Int)

    public init(stored: String) {
        let parts = stored.split(separator: ":")
        guard parts.count == 2, let value = Int(parts[1]), (0...9).contains(value) else { self = .all; return }
        switch parts[0] {
        case "exact": self = .exact(value)
        case "min": self = .atLeast(value)
        default: self = .all
        }
    }
    public var stored: String {
        switch self {
        case .all: return "all"
        case .exact(let value): return "exact:\(value)"
        case .atLeast(let value): return "min:\(value)"
        }
    }
    public var title: String {
        switch self {
        case .all: return "全部评分"
        case .exact(let value): return PhotoRating(value).title
        case .atLeast(let value): return "至少 \(value) 级"
        }
    }
    public func includes(_ score: Int) -> Bool {
        switch self {
        case .all: return true
        case .exact(let value): return score == value
        case .atLeast(let value): return score >= value
        }
    }
}
