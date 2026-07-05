//
//  GestureMappingTests.swift
//  TheClapperTests
//
//  Covers GestureActionMapping defaults and the v13 mapping "migration":
//  build 13 retired the "snap" gesture, so a saved-mappings blob from an
//  older install that still contains a snap row must FAIL to decode, which
//  makes ActionDispatcher.loadMappings() keep the new defaults. There is no
//  explicit migration code — decode-failure → defaults IS the migration —
//  so these tests pin that behavior down.
//

import XCTest
@testable import TheClapper

final class GestureMappingTests: XCTestCase {

    private let mappingsKey = "gesture_mappings"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: mappingsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: mappingsKey)
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultMappings() {
        let defaults = GestureActionMapping.defaults
        XCTAssertEqual(defaults.count, 3)
        XCTAssertEqual(action(for: .singleClap, in: defaults), .flipCamera)
        XCTAssertEqual(action(for: .doubleClap, in: defaults), .startStopRecording)
        XCTAssertEqual(action(for: .tripleClap, in: defaults), .takePhoto)
    }

    // MARK: - v13 migration (retired "snap" row must fail decode → defaults)

    /// Hand-encoded pre-build-13 saved-mappings blob: the shape the app wrote
    /// when GestureType still had a `snap = "snap"` case.
    private var legacyBlobWithSnapRow: Data {
        Data("""
        [
            {"gesture":"single_clap","action":"take_photo"},
            {"gesture":"double_clap","action":"start_stop_recording"},
            {"gesture":"triple_clap","action":"toggle_flashlight"},
            {"gesture":"snap","action":"take_photo"}
        ]
        """.utf8)
    }

    func testDecodingLegacyBlobContainingSnapRowThrows() {
        XCTAssertThrowsError(
            try JSONDecoder().decode([GestureActionMapping].self, from: legacyBlobWithSnapRow),
            "'snap' is no longer a GestureType raw value, so the whole array decode must throw"
        )
    }

    func testLoadMappingsFallsBackToDefaultsWhenSavedBlobContainsSnapRow() {
        UserDefaults.standard.set(legacyBlobWithSnapRow, forKey: mappingsKey)

        let dispatcher = ActionDispatcher(cameraService: CameraService())

        // The legacy blob must be rejected wholesale — including its valid
        // rows (triple_clap → toggle_flashlight above) — leaving defaults.
        XCTAssertEqual(dispatcher.mappings.count, 3)
        XCTAssertEqual(action(for: .singleClap, in: dispatcher.mappings), .flipCamera)
        XCTAssertEqual(action(for: .doubleClap, in: dispatcher.mappings), .startStopRecording)
        XCTAssertEqual(action(for: .tripleClap, in: dispatcher.mappings), .takePhoto)
    }

    func testLoadMappingsFallsBackToDefaultsOnGarbageBlob() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: mappingsKey)

        let dispatcher = ActionDispatcher(cameraService: CameraService())

        XCTAssertEqual(action(for: .singleClap, in: dispatcher.mappings), .flipCamera)
        XCTAssertEqual(action(for: .doubleClap, in: dispatcher.mappings), .startStopRecording)
        XCTAssertEqual(action(for: .tripleClap, in: dispatcher.mappings), .takePhoto)
    }

    // MARK: - Round trip (current shape loads; user edits persist)

    func testLoadMappingsReadsValidSavedBlob() {
        let saved = [
            GestureActionMapping(gesture: .singleClap, action: .toggleFlashlight),
            GestureActionMapping(gesture: .doubleClap, action: .takePhoto),
            GestureActionMapping(gesture: .tripleClap, action: .none)
        ]
        UserDefaults.standard.set(try! JSONEncoder().encode(saved), forKey: mappingsKey)

        let dispatcher = ActionDispatcher(cameraService: CameraService())

        XCTAssertEqual(action(for: .singleClap, in: dispatcher.mappings), .toggleFlashlight)
        XCTAssertEqual(action(for: .doubleClap, in: dispatcher.mappings), .takePhoto)
        XCTAssertEqual(action(for: .tripleClap, in: dispatcher.mappings), ActionType.none)
    }

    func testUpdateMappingPersistsAcrossDispatcherInstances() {
        let camera = CameraService()
        let first = ActionDispatcher(cameraService: camera)
        first.updateMapping(gesture: .singleClap, action: .startStopTimer)

        let second = ActionDispatcher(cameraService: camera)
        XCTAssertEqual(action(for: .singleClap, in: second.mappings), .startStopTimer)
        // Untouched rows keep their defaults.
        XCTAssertEqual(action(for: .doubleClap, in: second.mappings), .startStopRecording)
    }

    // MARK: - Helpers

    private func action(for gesture: GestureType, in mappings: [GestureActionMapping]) -> ActionType? {
        mappings.first(where: { $0.gesture == gesture })?.action
    }
}
