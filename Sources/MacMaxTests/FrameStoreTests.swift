import CoreGraphics
import MacMaxCore

func runFrameStoreTests(_ h: Harness) {
    let original = CGRect(x: 488, y: 198, width: 920, height: 683)
    let filled = CGRect(x: 0, y: 30, width: 1408, height: 851)

    h.test("a window Mac Max has not touched is not restorable") {
        let store = FrameStore<String>()
        h.expectEqual(store.restorable("w1", currentFrame: original), nil)
    }

    h.test("a filled window still in place is restorable to its previous frame") {
        let store = FrameStore<String>()
        store.record("w1", previousFrame: original, appliedFrame: filled, method: .nativeTiling)
        let record = store.restorable("w1", currentFrame: filled)
        h.expectEqual(record?.previousFrame, original)
        h.expectEqual(record?.method, .nativeTiling)
    }

    h.test("drift within tolerance is still restorable, because apps round their frames") {
        let store = FrameStore<String>()
        store.record("w1", previousFrame: original, appliedFrame: filled, method: .directResize)
        let drifted = CGRect(x: 1, y: 31, width: 1408, height: 851)
        h.expectEqual(store.restorable("w1", currentFrame: drifted)?.previousFrame, original)
    }

    h.test("a window the user has since moved fills fresh instead of restoring") {
        let store = FrameStore<String>()
        store.record("w1", previousFrame: original, appliedFrame: filled, method: .nativeTiling)
        let moved = CGRect(x: 300, y: 300, width: 1408, height: 851)
        h.expectEqual(store.restorable("w1", currentFrame: moved), nil)
    }

    h.test("a stale record is dropped, so it cannot resurrect after the window returns by chance") {
        let store = FrameStore<String>()
        store.record("w1", previousFrame: original, appliedFrame: filled, method: .nativeTiling)
        _ = store.restorable("w1", currentFrame: CGRect(x: 300, y: 300, width: 400, height: 400))
        h.expectEqual(store.count, 0)
        h.expectEqual(store.restorable("w1", currentFrame: filled), nil)
    }

    h.test("recording the same window twice updates rather than duplicates") {
        let store = FrameStore<String>()
        store.record("w1", previousFrame: original, appliedFrame: filled, method: .directResize)
        let second = CGRect(x: 10, y: 10, width: 200, height: 200)
        store.record("w1", previousFrame: second, appliedFrame: filled, method: .nativeTiling)
        h.expectEqual(store.count, 1)
        h.expectEqual(store.restorable("w1", currentFrame: filled)?.previousFrame, second)
    }

    h.test("forget removes a record") {
        let store = FrameStore<String>()
        store.record("w1", previousFrame: original, appliedFrame: filled, method: .directResize)
        store.forget("w1")
        h.expectEqual(store.count, 0)
    }

    h.test("the store evicts the oldest record once it is full") {
        let store = FrameStore<String>(tolerance: 2, capacity: 3)
        for index in 1...4 {
            store.record("w\(index)", previousFrame: original, appliedFrame: filled, method: .directResize)
        }
        h.expectEqual(store.count, 3)
        h.expectEqual(store.restorable("w1", currentFrame: filled), nil)
        h.expect(store.restorable("w4", currentFrame: filled) != nil, "the newest record must survive")
    }

    h.test("prune drops records whose windows are gone") {
        let store = FrameStore<String>()
        store.record("alive", previousFrame: original, appliedFrame: filled, method: .directResize)
        store.record("dead", previousFrame: original, appliedFrame: filled, method: .directResize)
        store.prune { $0 == "alive" }
        h.expectEqual(store.count, 1)
        h.expect(store.restorable("alive", currentFrame: filled) != nil, "the live window must survive pruning")
    }
}
