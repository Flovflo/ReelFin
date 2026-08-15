import XCTest
@testable import PlaybackEngine

final class PlayheadPublicationPolicyTests: XCTestCase {
    func testNewestPublicationWinsWhenOlderCompletionArrivesLast() {
        let policy = PlayheadPublicationPolicy()

        let first = policy.record(target: 0)
        let second = policy.record(target: 4_096)

        XCTAssertFalse(policy.shouldDeliver(first))
        XCTAssertTrue(policy.shouldDeliver(second))
    }

    func testRemovingLastServePublishesNoTargetAtNewestRevision() {
        let policy = PlayheadPublicationPolicy()

        _ = policy.record(target: 4_096)
        let empty = policy.record(target: nil)

        XCTAssertTrue(policy.shouldDeliver(empty))
        XCTAssertNil(empty.target)
    }

    func testCoordinatorDropsAnOlderPublicationThatArrivesAfterANewerRevision() async {
        let policy = PlayheadPublicationPolicy()
        let recorder = PlayheadDeliveryRecorder()
        let coordinator = PlayheadPublicationCoordinator(policy: policy) { target in
            await recorder.append(target)
        }

        let older = policy.record(target: 1_024)
        let newer = policy.record(target: 8_192)
        await coordinator.publish(newer)
        await coordinator.publish(older)

        let delivered = await recorder.values
        XCTAssertEqual(delivered, [8_192])
    }

    func testCoordinatorFinishesSuspendedOlderDeliveryBeforeApplyingPendingNewerTarget() async {
        let policy = PlayheadPublicationPolicy()
        let gate = SuspendedPlayheadDelivery()
        let coordinator = PlayheadPublicationCoordinator(policy: policy) { target in
            await gate.deliver(target)
        }
        let older = policy.record(target: 1_024)
        let olderTask = Task { await coordinator.publish(older) }
        await gate.waitUntilFirstDeliveryStarts()

        let newer = policy.record(target: 8_192)
        await coordinator.publish(newer)
        await gate.releaseFirstDelivery()
        await olderTask.value

        let delivered = await gate.values
        XCTAssertEqual(delivered, [1_024, 8_192])
    }

    func testTargetStateUsesLowestStarvedThenFurthestActiveAndRecomputesOnRemoval() {
        let state = PlayheadTargetState<String>()

        XCTAssertEqual(state.update(key: "a", offset: 8_192, waiting: false).target, 8_192)
        XCTAssertEqual(state.update(key: "b", offset: 2_048, waiting: true).target, 2_048)
        XCTAssertEqual(state.update(key: "b", offset: 2_048, waiting: false).target, 8_192)
        XCTAssertEqual(state.remove(key: "a").target, 2_048)
        XCTAssertNil(state.remove(key: "b").target)
    }

    func testStaleTaskTokenCannotRemoveReplacementRegistration() async {
        let registry = TokenTaskRegistry<String>()
        let stale = registry.reserve("request").token
        let replacement = registry.reserve("request").token

        XCTAssertFalse(registry.remove(key: "request", token: stale).removed)
        let task = Task<Void, Never> {}
        XCTAssertTrue(registry.attach(task, key: "request", token: replacement))
        XCTAssertTrue(registry.remove(key: "request", token: replacement).removed)
    }

    func testCancellationBeforeTaskAttachmentRejectsTheLateTask() async {
        let registry = TokenTaskRegistry<String>()
        let token = registry.reserve("request").token
        XCTAssertNil(registry.removeCurrent(key: "request"))
        let task = Task<Void, Never> {}
        XCTAssertFalse(registry.attach(task, key: "request", token: token))
        task.cancel()
    }

    func testReplacementReservationReturnsThePreviouslyAttachedTaskForCancellation() async {
        let registry = TokenTaskRegistry<String>()
        let original = registry.reserve("request")
        let task = Task<Void, Never> { await Task.yield() }
        XCTAssertTrue(registry.attach(task, key: "request", token: original.token))

        let replacement = registry.reserve("request")
        XCTAssertNotNil(replacement.replacedTask)
        replacement.replacedTask?.cancel()
        XCTAssertTrue(task.isCancelled)
    }
}

private actor PlayheadDeliveryRecorder {
    private(set) var values: [Int64] = []
    func append(_ value: Int64) { values.append(value) }
}

private actor SuspendedPlayheadDelivery {
    private(set) var values: [Int64] = []
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func deliver(_ target: Int64) async {
        values.append(target)
        guard values.count == 1 else { return }
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilFirstDeliveryStarts() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseFirstDelivery() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
