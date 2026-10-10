//
//  ActionDispatcherTests.swift
//  TheClapperTests
//
//  Covers ActionDispatcher's dispatch behavior and the gesture-aware trim
//  contract (gestureSpan = now − firstOnsetAt) as far as it is observable
//  in a simulator unit test.
//
//  SEAM NOTE (untestable without app changes — deliberately NOT made):
//  ActionDispatcher holds a concrete `final` CameraService (no protocol
//  seam), so the exact gestureSpan value it passes into
//  `cameraService.toggleRecording(gestureTriggered:gestureSpan:)` — and
//  CameraService's private `pendingStopTail`/`+0.35` tail math — cannot be
//  intercepted. What we CAN do:
//    1. pin the span formula itself against crafted firstOnsetAt Dates
//       (the same expression ActionDispatcher evaluates), and
//    2. drive the real dispatch path end-to-end and prove the CameraService
//       guard (`captureSession.isRunning` + active connection) keeps a
//       recording gesture safe with no running session — the audit's
//       CRITICAL #1 regression surface.
//

import XCTest
import Combine
@testable import TheClapper

final class ActionDispatcherTests: XCTestCase {

    private let mappingsKey = "gesture_mappings"
    private var cameraService: CameraService!
    private var dispatcher: ActionDispatcher!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: mappingsKey)
        cameraService = CameraService()
        dispatcher = ActionDispatcher(cameraService: cameraService)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: mappingsKey)
        dispatcher = nil
        cameraService = nil
        super.tearDown()
    }

    private func gesture(_ type: GestureType, firstOnsetAt: Date? = nil) -> DetectedGesture {
        DetectedGesture(type: type, timestamp: .now, confidence: 0.85, firstOnsetAt: firstOnsetAt)
    }

    /// Spins the main run loop until the pending main-queue blocks land.
    private func drainMainQueue() {
        let settle = expectation(description: "main queue drained")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)
    }

    // MARK: - Gesture-aware trim span contract

    func testGestureSpanFormulaMeasuresFromFirstOnset() {
        // The exact expression ActionDispatcher.dispatch evaluates before
        // calling toggleRecording: firstOnsetAt.map { Date().timeIntervalSince($0) }.
        // A stop gesture whose first clap was 1.2s ago must yield ~1.2s of
        // tail — the whole gesture, not just the final clap.
        let stopGesture = gesture(.doubleClap, firstOnsetAt: Date(timeIntervalSinceNow: -1.2))
        let span = stopGesture.firstOnsetAt.map { Date().timeIntervalSince($0) }

        XCTAssertNotNil(span)
        XCTAssertEqual(span!, 1.2, accuracy: 0.1)
    }

    func testGestureSpanIsNilWithoutFirstOnset() {
        let manualish = gesture(.doubleClap, firstOnsetAt: nil)
        let span = manualish.firstOnsetAt.map { Date().timeIntervalSince($0) }
        XCTAssertNil(span, "no firstOnsetAt → no tail trim (falls back to the default)")
    }

    // MARK: - Dispatch through the real CameraService (guard path)

    func testRecordingGestureWithoutRunningSessionIsSafeNoOp() {
        // Default mapping: doubleClap → startStopRecording. The capture
        // session is NOT running in a unit test, so CameraService's
        // startRecording guard must bail — no ObjC exception, no state flip.
        let stopGesture = gesture(.doubleClap, firstOnsetAt: Date(timeIntervalSinceNow: -0.8))

        dispatcher.dispatch(gesture: stopGesture)
        drainMainQueue()

        XCTAssertFalse(cameraService.isRecording)
        // The dispatcher still records that the mapped action ran.
        XCTAssertEqual(dispatcher.lastExecutedAction, .startStopRecording)
    }

    // MARK: - Dispatch behavior

    func testDispatchTogglesTimerAction() {
        dispatcher.updateMapping(gesture: .singleClap, action: .startStopTimer)

        dispatcher.dispatch(gesture: gesture(.singleClap))
        XCTAssertTrue(dispatcher.isTimerRunning)

        dispatcher.dispatch(gesture: gesture(.singleClap))
        XCTAssertFalse(dispatcher.isTimerRunning)

        drainMainQueue()
        XCTAssertEqual(dispatcher.lastExecutedAction, .startStopTimer)
    }

    func testDispatchOfNoneMappedGestureDoesNothing() {
        dispatcher.updateMapping(gesture: .tripleClap, action: .none)

        dispatcher.dispatch(gesture: gesture(.tripleClap))
        drainMainQueue()

        XCTAssertNil(dispatcher.lastExecutedAction, "gestures mapped to .none must not execute")
        XCTAssertFalse(dispatcher.isTimerRunning)
        XCTAssertFalse(cameraService.isRecording)
    }
}
