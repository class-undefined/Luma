import Foundation

public enum ThumbnailSize: Int, CaseIterable, Sendable {
    case tiny, small, medium, large, huge

    public var width: CGFloat { [128, 192, 272, 384, 512][rawValue] }
    public var title: String { ["很小", "小", "中等", "大", "很大"][rawValue] }

    public init(clamping index: Int) {
        self = Self(rawValue: min(4, max(0, index)))!
    }

    public func stepping(_ delta: Int) -> Self { Self(clamping: rawValue + delta) }
}

/// Converts wheel notches and accumulated trackpad motion into discrete steps.
/// Momentum from a Control gesture stays consumed after the modifier is released.
public struct ScrollStepAccumulator: Sendable {
    public struct Result: Equatable, Sendable {
        public let consumed: Bool
        public let step: Int
    }

    private var accumulated: Double = 0
    private var direction = 0
    private var lastTimestamp: TimeInterval = 0
    private var lastStepTimestamp: TimeInterval = -.infinity
    private var suppressMomentum = false
    public let threshold: Double
    public let cooldown: TimeInterval

    public init(threshold: Double = 28, cooldown: TimeInterval = 0.16) {
        self.threshold = threshold
        self.cooldown = cooldown
    }

    public mutating func handle(delta: Double, precise: Bool, control: Bool,
                                momentum: Bool, began: Bool = false,
                                timestamp: TimeInterval) -> Result {
        if momentum {
            return Result(consumed: control || suppressMomentum, step: 0)
        }
        if began || timestamp - lastTimestamp > 0.35 {
            accumulated = 0
            direction = 0
            suppressMomentum = false
        }
        lastTimestamp = timestamp
        guard control else {
            accumulated = 0
            direction = 0
            return Result(consumed: false, step: 0)
        }
        suppressMomentum = true
        guard delta.isFinite, delta != 0 else { return Result(consumed: true, step: 0) }
        let sign = delta > 0 ? 1 : -1
        guard precise else { return Result(consumed: true, step: sign) }
        if direction != sign { accumulated = 0 }
        direction = sign
        accumulated += delta
        guard abs(accumulated) >= threshold else { return Result(consumed: true, step: 0) }
        // Discard excess motion, so a fast gesture cannot queue up unwanted steps.
        accumulated = 0
        guard timestamp - lastStepTimestamp >= cooldown else { return Result(consumed: true, step: 0) }
        lastStepTimestamp = timestamp
        return Result(consumed: true, step: sign)
    }
}

public struct GalleryGeometry: Sendable {
    public let itemWidth: CGFloat
    public let itemHeight: CGFloat
    public let columns: Int
    public let horizontalInset: CGFloat
    public let gap: CGFloat

    public init(viewportWidth: CGFloat, size: ThumbnailSize) {
        gap = 16
        itemWidth = min(size.width, max(80, viewportWidth - 40))
        itemHeight = itemWidth * 2 / 3 + 32
        columns = max(1, Int((viewportWidth - 40 + gap) / (itemWidth + gap)))
        horizontalInset = max(20, (viewportWidth - CGFloat(columns) * itemWidth - CGFloat(columns - 1) * gap) / 2)
    }
}
