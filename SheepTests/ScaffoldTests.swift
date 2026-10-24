import XCTest
import CoreText
@testable import Sheep

final class ThemeTests: XCTestCase {
    func testNunitoIsRegistered() {
        let font = Theme.uiNunito(17, weight: 400)
        XCTAssertTrue(font.fontName.hasPrefix("Nunito"), "got \(font.fontName) — UIAppFonts not bundled?")
    }

    func testWeightAxisIsApplied() {
        for weight: CGFloat in [400, 700] {
            let font = Theme.uiNunito(17, weight: weight) as CTFont
            let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
            let wght = variation[NSNumber(value: Theme.wghtAxisTag)]?.doubleValue
            XCTAssertEqual(wght ?? -1, Double(weight), accuracy: 0.5, "wght axis not applied for \(weight)")
        }
    }

    func testItalicResolves() {
        XCTAssertTrue(Theme.uiNunito(17, weight: 400, italic: true).fontName.contains("Italic"))
    }
}

final class EventLogTests: XCTestCase {
    func testAppendAndReadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID()).jsonl")
        let log = EventLog(fileURL: { url })
        log.append(SheepEvent(type: .sessionStart, mode: .focus, title: "Ch.3", plannedMin: 75, answers: ["a", "b", "c"]))
        log.append(SheepEvent(type: .nudge, app: .instagram, tone: "firm", action: "back_to_focus", outcome: "ignored"))
        let events = log.readAll()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].type, .sessionStart)
        XCTAssertEqual(events[1].outcome, "ignored")
        let line = events[1].jsonLine()
        XCTAssertTrue(line.contains("\"type\":\"nudge\""))
        XCTAssertFalse(line.contains("null"), "nil fields must be omitted")
    }
}

final class GeminiClientTests: XCTestCase {
    struct Brief: Codable, Equatable { var headline: String }

    func testNoKeyReturnsFallbackImmediately() async {
        let client = GeminiClient(apiKey: "", model: nil)
        let prompt = GeminiPrompt(name: "t", system: "s", user: "u", schema: ["type": "object"], temperature: 0.5)
        let result = await client.generate(Brief.self, prompt, fallback: Brief(headline: "fallback"))
        XCTAssertEqual(result.source, .fallback)
        XCTAssertEqual(result.value.headline, "fallback")
    }

    func testSchemaNormalisation() {
        let schema: JSONValue = ["type": "object", "properties": ["a": ["type": "array", "items": ["type": "string"], "minItems": 3]]]
        guard case .object(let o) = schema.geminiSchema, case .object(let props) = o["properties"],
              case .object(let a) = props["a"] else { return XCTFail() }
        XCTAssertEqual(o["type"], "OBJECT")
        XCTAssertEqual(a["type"], "ARRAY")
        XCTAssertEqual(a["minItems"], "3")
    }

    func testDecodeResponseEnvelope() throws {
        let body = #"{"candidates":[{"content":{"parts":[{"text":"{\"headline\":\"hi\"}"}]}}]}"#
        let brief = try GeminiClient.decodeResponse(Brief.self, from: Data(body.utf8))
        XCTAssertEqual(brief.headline, "hi")
    }
}

final class AppStateTests: XCTestCase {
    func testPersistsAcrossInstances() {
        let name = "sheep-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let a = AppState(defaults: defaults)
        a.setMode(.rest)
        a.progress.add(130)
        XCTAssertEqual(a.mode, .rest, "picker can sit in Rest while the app is running")
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.mode, .idle, "Rest with no session must not survive relaunch")
        XCTAssertEqual(b.progress.xp, 130)
        XCTAssertEqual(b.progress.level, 1)
    }

    func testLoadDropsModeWhenNoMatchingSession() {
        let name = "sheep-tests-mode-load-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = AppState(defaults: defaults)

        state.setMode(.focus)
        XCTAssertEqual(state.mode, .focus)
        XCTAssertEqual(AppState(defaults: defaults).mode, .idle)

        state.setMode(.rest)
        XCTAssertEqual(AppState(defaults: defaults).mode, .idle)

        state.setMode(.play)
        XCTAssertEqual(AppState(defaults: defaults).mode, .idle)
    }

    func testLoadKeepsModeWhenMatchingSessionIsRunning() {
        let name = "sheep-tests-mode-keep-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let state = AppState(defaults: defaults)

        state.activeSession = FocusSession(answers: ["a"], title: "Ch.3", opener: "", watchOut: "",
                                           workstream: "", checklist: [], pomodoros: 1, pomodoroMinutes: 25,
                                           startedAt: start)
        state.setMode(.focus)
        XCTAssertEqual(AppState(defaults: defaults).mode, .focus)
        XCTAssertNotNil(AppState(defaults: defaults).activeSession)

        state.activeSession = nil
        state.restSession = RestSession(activity: "Walk", limitMinutes: 30, startedAt: start)
        state.setMode(.rest)
        XCTAssertEqual(AppState(defaults: defaults).mode, .rest)

        state.restSession = nil
        state.playSession = PlaySession(limitMinutes: 60, startedAt: start)
        state.setMode(.play)
        XCTAssertEqual(AppState(defaults: defaults).mode, .play)
    }

    func testLoadTreatsEndedRestOrPlaySessionAsIdle() {
        let name = "sheep-tests-mode-ended-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let state = AppState(defaults: defaults)

        state.restSession = RestSession(activity: "Walk", limitMinutes: 30, startedAt: start,
                                        endedAt: start.addingTimeInterval(60))
        state.setMode(.rest)
        XCTAssertEqual(AppState(defaults: defaults).mode, .idle)

        state.restSession = nil
        state.playSession = PlaySession(limitMinutes: 60, startedAt: start,
                                        endedAt: start.addingTimeInterval(60))
        state.setMode(.play)
        XCTAssertEqual(AppState(defaults: defaults).mode, .idle)
    }

    @MainActor
    func testDeepLinks() {
        let state = AppState(defaults: UserDefaults(suiteName: "sheep-tests-\(UUID())")!)
        let router = Router()
        XCTAssertTrue(router.handle(url: URL(string: "sheep://open/youtube")!, state: state))
        XCTAssertEqual(router.presentedWrapper, .youtube)
        XCTAssertTrue(router.handle(url: URL(string: "sheep://mode/rest")!, state: state))
        XCTAssertEqual(state.mode, .rest)
        XCTAssertEqual(router.path, [.rest])
        XCTAssertFalse(router.handle(url: URL(string: "sheep://open/tiktok")!, state: state))
    }
}

final class XPRulesTests: XCTestCase {
    func testSessionEnd() {
        XCTAssertEqual(XPRules.sessionEnd(focusedMinutes: 25, fast: false, completed: true, reflectionBonus: 20), 50 + 50 + 20)
        XCTAssertEqual(XPRules.sessionEnd(focusedMinutes: 3, fast: true, completed: false, reflectionBonus: 99), 30 + 50)
        XCTAssertEqual(XPRules.restOrPlay(actualMinutes: 50, limitMinutes: 45), 0)
    }

    func testProgressNeverNegative() {
        var p = Progress(xp: 5)
        p.add(XPRules.ignoredNudge)
        XCTAssertEqual(p.xp, 0)
    }
}
