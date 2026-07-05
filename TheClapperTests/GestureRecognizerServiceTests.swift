//
//  GestureRecognizerServiceTests.swift
//  TheClapperTests
//
//  Covers the onset-count → gesture resolution contract of
//  GestureRecognizerService (audit pass 5–6: "no regression tests for
//  gesture windows"):
//    - single / double / triple resolution by onset count
//    - the 0.6s inter-clap window (an onset past it resolves the previous
//      sequence immediately and starts a new one)
//    - the 0.65s patternWaitTime resolving a finished sequence
//    - firstOnsetAt carried through on the emitted gesture (the value the
//      gesture-aware stop-trim math depends on)
//
//  Technique: onsets are injected as crafted Dates via onTransientDetected,
//  and emissions are collected from the gestureRecognized publisher while
//  XCTest's expectation wait spins the main run loop (which is what fires
//  the service's internal Timer).
//

import XCTest
import Combine
@testable import TheClapper

final class GestureRecognizerServiceTests: XCTestCase {

    private var service: GestureRecognizerService!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        service = GestureRecognizerService()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        service = nil
        super.tearDown()
    }

    /// Subscribes to `gestureRecognized`, runs `feed`, then spins the run loop
    /// until `count` gestures arrive (or `timeout` elapses). The wait is what
    /// lets the 0.65s patternWaitTime Timer fire.
    private func collectGestures(count: Int,
                                 timeout: TimeInterval = 3.0,
                                 feed: () -> Void) -> [DetectedGesture] {
        var received: [DetectedGesture] = []
        let exp = expectation(description: "gestureRecognized emitted \(count) gesture(s)")
        exp.expectedFulfillmentCount = count
        service.gestureRecognized
            .sink { gesture in
                received.append(gesture)
                exp.fulfill()
            }
            .store(in: &cancellables)
        feed()
        wait(for: [exp], timeout: timeout)
        return received
    }

    // MARK: - Resolution by onset count

    func testSingleOnsetResolvesToSingleClap() {
        let onset = Date()
        let gestures = collectGestures(count: 1) {
            service.onTransientDetected(at: onset)
        }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(gestures[0].type, .singleClap)
        XCTAssertEqual(gestures[0].confidence, 0.85)
    }

    func testTwoOnsetsWithinWindowResolveToDoubleClap() {
        let first = Date()
        let gestures = collectGestures(count: 1) {
            service.onTransientDetected(at: first)
            // 0.3s apart — comfortably inside the 0.6s inter-clap window.
            service.onTransientDetected(at: first.addingTimeInterval(0.3))
        }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(gestures[0].type, .doubleClap)
    }

    func testThreeOnsetsWithinWindowResolveToTripleClap() {
        let first = Date()
        let gestures = collectGestures(count: 1) {
            service.onTransientDetected(at: first)
            service.onTransientDetected(at: first.addingTimeInterval(0.3))
            service.onTransientDetected(at: first.addingTimeInterval(0.6))
        }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(gestures[0].type, .tripleClap)
    }

    func testFourOrMoreOnsetsClampToTripleClap() {
        let first = Date()
        let gestures = collectGestures(count: 1) {
            for i in 0..<4 {
                service.onTransientDetected(at: first.addingTimeInterval(Double(i) * 0.2))
            }
        }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(gestures[0].type, .tripleClap, "counts above three fall into the default (triple) case")
    }

    // MARK: - Inter-clap window edge

    func testOnsetJustInsideWindowEdgeStaysInSequence() {
        // interval > maxInterClapInterval (0.6s) starts a NEW sequence. An onset
        // just inside the edge must stay in the running sequence. (Exactly 0.6
        // isn't asserted: Date arithmetic makes `t.addingTimeInterval(0.6)`
        // land a few ULPs above 0.6, so the strict `>` flips at the literal
        // boundary — a floating-point artifact, not app behavior.)
        let first = Date()
        let gestures = collectGestures(count: 1) {
            service.onTransientDetected(at: first)
            service.onTransientDetected(at: first.addingTimeInterval(0.59))
        }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(gestures[0].type, .doubleClap)
    }

    func testOnsetBeyondWindowResolvesPreviousSequenceAndStartsNew() {
        let first = Date()
        let second = first.addingTimeInterval(0.75) // > 0.6s → new sequence
        let gestures = collectGestures(count: 2) {
            service.onTransientDetected(at: first)
            // This call synchronously resolves the timed-out first sequence
            // (single clap), then seeds a new one that the pattern timer resolves.
            service.onTransientDetected(at: second)
        }
        XCTAssertEqual(gestures.count, 2)
        XCTAssertEqual(gestures[0].type, .singleClap)
        XCTAssertEqual(gestures[0].firstOnsetAt, first)
        XCTAssertEqual(gestures[1].type, .singleClap)
        XCTAssertEqual(gestures[1].firstOnsetAt, second)
    }

    // MARK: - firstOnsetAt (the stop-trim anchor)

    func testFirstOnsetTimestampIsCarriedOnEmittedGesture() {
        // The gesture-aware trim cuts back to the FIRST clap of the stop
        // gesture — so the emitted gesture must carry the first onset, not
        // the last.
        let first = Date(timeIntervalSinceNow: -0.4)
        let second = first.addingTimeInterval(0.35)
        let gestures = collectGestures(count: 1) {
            service.onTransientDetected(at: first)
            service.onTransientDetected(at: second)
        }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(gestures[0].type, .doubleClap)
        XCTAssertEqual(gestures[0].firstOnsetAt, first,
                       "firstOnsetAt must anchor to the sequence's FIRST onset")
    }

    func testLastGestureAndRecentGesturesArePublished() {
        let onset = Date()
        _ = collectGestures(count: 1) {
            service.onTransientDetected(at: onset)
        }
        // lastGesture/recentGestures are set via DispatchQueue.main.async;
        // spin the run loop briefly to let that block land.
        let settle = expectation(description: "main queue drained")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)

        XCTAssertEqual(service.lastGesture?.type, .singleClap)
        XCTAssertEqual(service.recentGestures.count, 1)
        XCTAssertEqual(service.recentGestures.first?.type, .singleClap)
    }
}
