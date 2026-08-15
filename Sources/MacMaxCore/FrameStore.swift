import CoreGraphics
import Foundation

/// How a window was filled, which decides how it gets restored.
public enum FillMethod: Equatable, Sendable {
    /// macOS's own Fill command, undone with Return to Previous Size.
    case nativeTiling
    /// A frame Mac Max set itself, undone by setting the frame back.
    case directResize
}

public struct FillRecord: Equatable, Sendable {
    /// Where the window was before Mac Max filled it.
    public let previousFrame: CGRect
    /// Where it ended up, used to tell whether the user has moved it since.
    public let appliedFrame: CGRect
    public let method: FillMethod

    public init(previousFrame: CGRect, appliedFrame: CGRect, method: FillMethod) {
        self.previousFrame = previousFrame
        self.appliedFrame = appliedFrame
        self.method = method
    }
}

/// Remembers which windows Mac Max filled, and where they were beforehand.
///
/// Whether a window counts as filled is decided from this record rather than by
/// measuring the window against the screen: native Fill insets the window when
/// tiling margins are enabled, so a geometric test would be wrong on exactly the
/// machines that have that setting on.
public final class FrameStore<Key: Hashable> {
    public let tolerance: CGFloat
    public let capacity: Int

    private var records: [Key: FillRecord] = [:]
    private var order: [Key] = []
    private let lock = NSLock()

    public init(tolerance: CGFloat = 2, capacity: Int = 64) {
        self.tolerance = tolerance
        self.capacity = capacity
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return records.count
    }

    public func record(_ key: Key, previousFrame: CGRect, appliedFrame: CGRect, method: FillMethod) {
        lock.lock(); defer { lock.unlock() }
        if records[key] == nil { order.append(key) }
        records[key] = FillRecord(previousFrame: previousFrame, appliedFrame: appliedFrame, method: method)
        while order.count > capacity {
            let oldest = order.removeFirst()
            records.removeValue(forKey: oldest)
        }
    }

    public func forget(_ key: Key) {
        lock.lock(); defer { lock.unlock() }
        removeLocked(key)
    }

    /// The record for `key`, but only while the window still sits where Mac Max put
    /// it. A window the user has moved or resized since is treated as un-filled and
    /// its stale record is dropped, so the next click fills fresh.
    public func restorable(_ key: Key, currentFrame: CGRect) -> FillRecord? {
        lock.lock(); defer { lock.unlock() }
        guard let record = records[key] else { return nil }
        guard AXGeometry.matches(currentFrame, record.appliedFrame, tolerance: tolerance) else {
            removeLocked(key)
            return nil
        }
        return record
    }

    /// Drops records for windows that no longer exist.
    public func prune(isValid: (Key) -> Bool) {
        lock.lock(); defer { lock.unlock() }
        for key in order where !isValid(key) { removeLocked(key) }
    }

    private func removeLocked(_ key: Key) {
        records.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }
}
