import XCTest
@testable import PlaybackEngine

@MainActor
final class PlaybackStateMachineTests: XCTestCase {

    // MARK: - A. Valid Transitions

    func testIdleToPreparing() {
        let sm = PlaybackStateMachine()
        XCTAssertTrue(sm.transition(to: .preparing))
        XCTAssertEqual(sm.state, .preparing)
        XCTAssertEqual(sm.previousState, .idle)
    }

    func testPreparingToReady() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        XCTAssertTrue(sm.transition(to: .ready))
        XCTAssertEqual(sm.state, .ready)
    }

    func testPreparingToPlaying() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        XCTAssertTrue(sm.transition(to: .playing))
    }

    func testPlayingToPaused() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        XCTAssertTrue(sm.transition(to: .paused))
        XCTAssertEqual(sm.state, .paused)
    }

    func testPlayingToBuffering() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        XCTAssertTrue(sm.transition(to: .buffering))
        XCTAssertEqual(sm.state, .buffering)
    }

    func testPlayingToSeeking() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        XCTAssertTrue(sm.transition(to: .seeking))
        XCTAssertEqual(sm.state, .seeking)
    }

    func testPlayingToEnded() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        XCTAssertTrue(sm.transition(to: .ended))
        XCTAssertEqual(sm.state, .ended)
    }

    func testPlayingToStalled() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        XCTAssertTrue(sm.transition(to: .stalled))
        XCTAssertEqual(sm.state, .stalled)
    }

    func testPausedToPlaying() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        sm.transition(to: .paused)
        XCTAssertTrue(sm.transition(to: .playing))
    }

    func testSeekingToPlaying() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        sm.transition(to: .seeking)
        XCTAssertTrue(sm.transition(to: .playing))
    }

    func testBufferingToPlaying() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        sm.transition(to: .buffering)
        XCTAssertTrue(sm.transition(to: .playing))
    }

    func testEndedToPreparing_allowsReplay() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        sm.transition(to: .ended)
        XCTAssertTrue(sm.transition(to: .preparing))
    }

    // MARK: - B. Invalid Transitions

    func testIdleToPlaying_isInvalid() {
        let sm = PlaybackStateMachine()
        XCTAssertFalse(sm.transition(to: .playing))
        XCTAssertEqual(sm.state, .idle)
    }

    func testIdleToPaused_isInvalid() {
        let sm = PlaybackStateMachine()
        XCTAssertFalse(sm.transition(to: .paused))
        XCTAssertEqual(sm.state, .idle)
    }

    func testPreparingToSeeking_isInvalid() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        XCTAssertFalse(sm.transition(to: .seeking))
    }

    func testEndedToPlaying_isInvalid() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        sm.transition(to: .ended)
        XCTAssertFalse(sm.transition(to: .playing))
    }

    // MARK: - C. Always-Valid Transitions

    func testAnyStateToFailed_isAlwaysValid() {
        for state in UnifiedPlaybackState.allCases {
            let sm = PlaybackStateMachine()
            sm.forceState(state)
            XCTAssertTrue(sm.transition(to: .failed), "Should transition to .failed from \(state)")
        }
    }

    func testAnyStateToIdle_isAlwaysValid() {
        for state in UnifiedPlaybackState.allCases {
            let sm = PlaybackStateMachine()
            sm.forceState(state)
            XCTAssertTrue(sm.transition(to: .idle), "Should transition to .idle from \(state)")
        }
    }

    // MARK: - D. No Infinite Loops

    func testFailedCanRetry() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .failed)
        // Can retry from failed
        XCTAssertTrue(sm.transition(to: .retrying))
        XCTAssertTrue(sm.transition(to: .preparing))
    }

    func testStalledCanRetry() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        sm.transition(to: .stalled)
        XCTAssertTrue(sm.transition(to: .retrying))
        XCTAssertTrue(sm.transition(to: .preparing))
    }

    // MARK: - E. Force State

    func testForceState_bypassesValidation() {
        let sm = PlaybackStateMachine()
        sm.forceState(.playing)
        XCTAssertEqual(sm.state, .playing)
    }

    // MARK: - F. Reset

    func testReset_goesToIdle() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        sm.reset()
        XCTAssertEqual(sm.state, .idle)
    }

    // MARK: - G. Transition Callback

    func testOnTransition_isCalled() {
        let sm = PlaybackStateMachine()
        var transitions: [(UnifiedPlaybackState, UnifiedPlaybackState)] = []
        sm.onTransition = { from, to in
            transitions.append((from, to))
        }
        sm.transition(to: .preparing)
        sm.transition(to: .playing)
        XCTAssertEqual(transitions.count, 2)
        XCTAssertEqual(transitions[0].0, .idle)
        XCTAssertEqual(transitions[0].1, .preparing)
        XCTAssertEqual(transitions[1].0, .preparing)
        XCTAssertEqual(transitions[1].1, .playing)
    }

    // MARK: - H. State Properties

    func testIsActive() {
        XCTAssertFalse(UnifiedPlaybackState.idle.isActive)
        XCTAssertTrue(UnifiedPlaybackState.playing.isActive)
        XCTAssertTrue(UnifiedPlaybackState.paused.isActive)
        XCTAssertTrue(UnifiedPlaybackState.buffering.isActive)
        XCTAssertFalse(UnifiedPlaybackState.ended.isActive)
        XCTAssertFalse(UnifiedPlaybackState.failed.isActive)
    }

    func testIsLoading() {
        XCTAssertTrue(UnifiedPlaybackState.preparing.isLoading)
        XCTAssertTrue(UnifiedPlaybackState.buffering.isLoading)
        XCTAssertTrue(UnifiedPlaybackState.stalled.isLoading)
        XCTAssertTrue(UnifiedPlaybackState.retrying.isLoading)
        XCTAssertFalse(UnifiedPlaybackState.playing.isLoading)
        XCTAssertFalse(UnifiedPlaybackState.paused.isLoading)
    }

    // MARK: - I. Teardown During Preparation

    func testTeardownDuringPreparing() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        XCTAssertTrue(sm.transition(to: .failed))
        XCTAssertEqual(sm.state, .failed)
    }

    func testResetDuringPreparing() {
        let sm = PlaybackStateMachine()
        sm.transition(to: .preparing)
        sm.reset()
        XCTAssertEqual(sm.state, .idle)
    }
}
