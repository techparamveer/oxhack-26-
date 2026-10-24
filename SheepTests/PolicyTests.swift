import XCTest
import JavaScriptCore
@testable import Sheep

final class PolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        suiteName = "PolicyTests-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: Section detection

    func testInstagramSections() {
        let cases: [(String, AppSection)] = [
            ("/", .feed),
            ("", .feed),
            ("/explore/", .feed),
            ("/p/Cx1abc/", .feed),
            ("/stories/someone/123/", .feed),
            ("/reels/", .reels),
            ("/reels", .reels),
            ("/reels/Cx1/", .reels),
            ("/reel/Cx1/", .reels),
            ("/reel/Cx1", .reels),
            ("/REELS/", .reels),
            ("/someone/reels/", .reels),
            ("/reels/?igsh=abc", .reels),
            ("/reel/Cx1/?utm_source=ig_web#x", .reels),
            ("/direct/inbox/", .dms),
            ("/direct/t/123", .dms),
            ("/direct/t/123/?foo=bar", .dms),
            ("/direct", .dms),
            ("/?next=/direct/inbox/", .feed),
            ("/explore/?q=reels", .feed),
            ("https://www.instagram.com/reel/Cx1/", .reels),
            ("https://www.instagram.com/direct/inbox/", .dms),
            ("https://www.instagram.com/", .feed),
        ]
        for (path, expected) in cases {
            XCTAssertEqual(Policy.section(app: .instagram, path: path), expected, "instagram \(path)")
        }
    }

    func testYouTubeSections() {
        let cases: [(String, AppSection)] = [
            ("/", .feed),
            ("/watch?v=abc", .feed),
            ("/feed/subscriptions", .feed),
            ("/results?search_query=shorts", .feed),
            ("/shorts/abc", .shorts),
            ("/shorts/abc?feature=share", .shorts),
            ("/shorts", .shorts),
            ("/Shorts/abc", .shorts),
            ("/@channel/shorts", .feed),
            ("/reels/", .feed),
            ("https://m.youtube.com/shorts/abc", .shorts),
        ]
        for (path, expected) in cases {
            XCTAssertEqual(Policy.section(app: .youtube, path: path), expected, "youtube \(path)")
        }
    }

    // MARK: Full policy table

    func testPolicyTable() {
        let blockedInFocus: Set<AppSection> = [.reels, .dms, .shorts]
        for mode in Mode.allCases {
            for app in WrappedApp.allCases {
                for section in Policy.sections(of: app) {
                    let expected = mode == .focus ? !blockedInFocus.contains(section) : true
                    XCTAssertEqual(Policy.isAllowed(section: section, mode: mode, defaults: defaults), expected, "\(mode) \(app) \(section)")
                }
            }
        }
    }

    func testIsAllowedByPath() {
        let table: [(WrappedApp, String, Mode, Bool)] = [
            (.instagram, "/", .focus, true),
            (.instagram, "/explore/", .focus, true),
            (.instagram, "/reels/", .focus, false),
            (.instagram, "/reel/Cx1/", .focus, false),
            (.instagram, "/direct/inbox/", .focus, false),
            (.instagram, "/direct/t/123", .focus, false),
            (.youtube, "/", .focus, true),
            (.youtube, "/watch?v=abc", .focus, true),
            (.youtube, "/shorts/abc", .focus, false),
        ]
        for (app, path, mode, expected) in table {
            XCTAssertEqual(Policy.isAllowed(app: app, path: path, mode: mode, defaults: defaults), expected, "\(app) \(path) \(mode)")
        }
        for mode in [Mode.rest, .play, .idle] {
            for (app, path) in [(WrappedApp.instagram, "/reels/"), (.instagram, "/direct/inbox/"), (.youtube, "/shorts/abc"), (.instagram, "/")] {
                XCTAssertTrue(Policy.isAllowed(app: app, path: path, mode: mode, defaults: defaults), "\(app) \(path) \(mode)")
            }
        }
    }

    func testBlockedSections() {
        XCTAssertEqual(Policy.blockedSections(app: .instagram, mode: .focus, defaults: defaults), [.reels, .dms])
        XCTAssertEqual(Policy.blockedSections(app: .youtube, mode: .focus, defaults: defaults), [.shorts])
        for mode in [Mode.rest, .play, .idle] {
            for app in WrappedApp.allCases { XCTAssertTrue(Policy.blockedSections(app: app, mode: mode, defaults: defaults).isEmpty) }
        }
    }

    // MARK: Blocked in Focus setting

    func testBlockedInFocusDefaultsToAllThree() {
        XCTAssertEqual(Policy.blockedSections(in: .focus, defaults: defaults), [.reels, .dms, .shorts])
        for mode in [Mode.rest, .play, .idle] { XCTAssertTrue(Policy.blockedSections(in: mode, defaults: defaults).isEmpty) }
    }

    func testBlockedInFocusSettingDrivesPolicy() {
        Policy.setBlockedInFocus([.reels], defaults: defaults)
        XCTAssertEqual(defaults.array(forKey: "sheep.blockedInFocus") as? [String], ["reels"])
        XCTAssertFalse(Policy.isAllowed(app: .instagram, path: "/reels/", mode: .focus, defaults: defaults))
        XCTAssertTrue(Policy.isAllowed(app: .instagram, path: "/direct/inbox/", mode: .focus, defaults: defaults))
        XCTAssertTrue(Policy.isAllowed(app: .youtube, path: "/shorts/abc", mode: .focus, defaults: defaults))
        XCTAssertEqual(Policy.hidingCSS(app: .youtube, mode: .focus, defaults: defaults), "")
        XCTAssertFalse(Policy.hidingCSS(app: .instagram, mode: .focus, defaults: defaults).contains("/direct/"))

        Policy.setBlockedInFocus([], defaults: defaults)
        XCTAssertTrue(Policy.blockedSections(in: .focus, defaults: defaults).isEmpty)

        defaults.set(["feed", "shorts", "bogus"], forKey: Policy.blockedInFocusKey)
        XCTAssertEqual(Policy.blockedSections(in: .focus, defaults: defaults), [.shorts], "feed is never blocked")
        XCTAssertTrue(Policy.isAllowed(app: .youtube, path: "/", mode: .focus, defaults: defaults))
    }

    // MARK: CSS

    func testCSSEmptyWhenNothingBlocked() {
        for mode in [Mode.rest, .play, .idle] {
            for app in WrappedApp.allCases {
                XCTAssertEqual(Policy.hidingCSS(app: app, mode: mode, defaults: defaults), "", "\(app) \(mode)")
            }
        }
    }

    func testFocusCSSHidesEntryPoints() {
        let ig = Policy.hidingCSS(app: .instagram, mode: .focus, defaults: defaults)
        XCTAssertTrue(ig.contains(#"a[href*="/reels/"]"#))
        XCTAssertTrue(ig.contains(#"a[href^="/direct/"]"#))
        XCTAssertTrue(ig.contains(#"a[href*="/direct/"]"#))
        XCTAssertTrue(ig.contains("display: none !important"))
        XCTAssertFalse(ig.contains("shorts"))

        let yt = Policy.hidingCSS(app: .youtube, mode: .focus, defaults: defaults)
        XCTAssertTrue(yt.contains(#"a[href*="/shorts"]"#))
        XCTAssertTrue(yt.contains("ytm-reel-shelf-renderer"))
        XCTAssertTrue(yt.contains("ytm-shorts-lockup-view-model"))
        XCTAssertFalse(yt.contains("/direct/"))
        // One rule per selector.
        XCTAssertEqual(yt.components(separatedBy: "\n").count, Policy.hidingSelectors(app: .youtube, section: .shorts).count)
    }

    // MARK: Hosts

    func testAppHosts() {
        XCTAssertTrue(Policy.isAppHost("www.instagram.com", app: .instagram))
        XCTAssertTrue(Policy.isAppHost("l.instagram.com", app: .instagram))
        XCTAssertTrue(Policy.isAppHost("M.YouTube.com", app: .youtube))
        XCTAssertTrue(Policy.isAppHost("accounts.google.com", app: .youtube))
        XCTAssertFalse(Policy.isAppHost("example.com", app: .instagram))
        XCTAssertFalse(Policy.isAppHost("notinstagram.com", app: .instagram))
        XCTAssertFalse(Policy.isAppHost("www.youtube.com", app: .instagram))
        XCTAssertFalse(Policy.isAppHost(nil, app: .youtube))
    }

    // MARK: Message parsing

    func testMessageParsing() {
        XCTAssertEqual(WrapperMessage.parse(["type": "nav", "path": "/reels/"]), .nav(path: "/reels/"))
        XCTAssertEqual(WrapperMessage.parse(["type": "scroll", "px": NSNumber(value: 1200), "activeSec": NSNumber(value: 4), "path": "/"]),
                       .scroll(px: 1200, activeSec: 4, path: "/"))
        XCTAssertNil(WrapperMessage.parse(["type": "scroll", "px": NSNumber(value: 0), "activeSec": NSNumber(value: 0), "path": "/"]))
        XCTAssertNil(WrapperMessage.parse(["type": "content", "text": "hello"]))
        XCTAssertNil(WrapperMessage.parse("nav"))
    }
}

/// Runs the real `inject.js` in JavaScriptCore against a fake window/history/document.
final class InjectScriptTests: XCTestCase {
    private func makeContext(path: String = "/") throws -> (JSContext, () -> [[String: Any]]) {
        let source = WrapperController.injectSource
        XCTAssertFalse(source.isEmpty, "inject.js not bundled")
        let ctx = try XCTUnwrap(JSContext())
        ctx.exceptionHandler = { _, e in XCTFail("JS exception: \(e?.toString() ?? "?")") }
        ctx.evaluateScript("""
        var window = this;
        var __posted = [];
        var __listeners = {};
        var __intervals = [];
        window.location = { pathname: '\(path)' };
        window.scrollY = 0;
        window.webkit = { messageHandlers: { sheep: { postMessage: function (m) { __posted.push(JSON.parse(JSON.stringify(m))); } } } };
        window.addEventListener = function (n, f) { (__listeners[n] = __listeners[n] || []).push(f); };
        window.__fire = function (n, e) { (__listeners[n] || []).forEach(function (f) { f(e || {}); }); };
        window.setInterval = function (f) { __intervals.push(f); return __intervals.length; };
        window.__tick = function (n) { for (var i = 0; i < n; i++) { __intervals.forEach(function (f) { f(); }); } };
        window.history = {
          pushState: function (s, t, url) { window.location.pathname = url; },
          replaceState: function (s, t, url) { window.location.pathname = url; }
        };
        var __styles = [];
        window.document = {
          head: { appendChild: function (el) { el.parentNode = this; __styles.push(el); },
                  removeChild: function (el) { __styles = __styles.filter(function (s) { return s !== el; }); el.parentNode = null; } },
          getElementById: function (id) { return __styles.filter(function (s) { return s.id === id; })[0] || null; },
          createElement: function (tag) { return { tagName: tag, textContent: '' }; }
        };
        """)
        ctx.evaluateScript(source)
        let posted: () -> [[String: Any]] = {
            (ctx.objectForKeyedSubscript("__posted").toArray() as? [[String: Any]]) ?? []
        }
        return (ctx, posted)
    }

    func testPostsInitialPathAndSPANavigation() throws {
        let (ctx, posted) = try makeContext(path: "/")
        XCTAssertEqual(posted().first?["type"] as? String, "nav")
        XCTAssertEqual(posted().first?["path"] as? String, "/")

        ctx.evaluateScript("history.pushState({}, '', '/reels/');")
        XCTAssertEqual(posted().last?["path"] as? String, "/reels/")

        ctx.evaluateScript("history.replaceState({}, '', '/reels/');") // same path → no duplicate
        XCTAssertEqual(posted().count, 2)

        ctx.evaluateScript("window.location.pathname = '/'; window.__fire('popstate');")
        XCTAssertEqual(posted().last?["path"] as? String, "/")
        XCTAssertEqual(posted().count, 3)
    }

    func testScrollReportedEveryFiveSecondsOnlyWhenScrolled() throws {
        let (ctx, posted) = try makeContext()
        ctx.evaluateScript("window.__tick(5);")
        XCTAssertTrue(posted().allSatisfy { $0["type"] as? String == "nav" }, "no scroll message without scrolling")

        // Scroll in 3 of the next 5 seconds.
        ctx.evaluateScript("""
        window.scrollY = 300; window.__fire('scroll', { target: window.document }); window.__tick(1);
        window.__tick(1);
        window.scrollY = 700; window.__fire('scroll', { target: window.document }); window.__tick(1);
        window.scrollY = 600; window.__fire('scroll', { target: window.document }); window.__tick(1);
        window.__tick(1);
        """)
        let scroll = try XCTUnwrap(posted().last { $0["type"] as? String == "scroll" })
        XCTAssertEqual((scroll["px"] as? NSNumber)?.doubleValue, 800)
        XCTAssertEqual((scroll["activeSec"] as? NSNumber)?.doubleValue, 3)
        XCTAssertEqual(scroll["path"] as? String, "/")
    }

    func testSetCSSMaintainsSingleStyle() throws {
        let (ctx, _) = try makeContext()
        ctx.evaluateScript("window.__sheepSetCSS('a { display: none }'); window.__sheepSetCSS('b { display: none }');")
        XCTAssertEqual(ctx.evaluateScript("__styles.length").toInt32(), 1)
        XCTAssertEqual(ctx.evaluateScript("__styles[0].textContent").toString(), "b { display: none }")
        // Removed by the SPA → re-inserted on the next tick.
        ctx.evaluateScript("__styles = []; window.__tick(1);")
        XCTAssertEqual(ctx.evaluateScript("__styles.length").toInt32(), 1)
        ctx.evaluateScript("window.__sheepSetCSS('');")
        XCTAssertEqual(ctx.evaluateScript("__styles.length").toInt32(), 0)
    }
}
