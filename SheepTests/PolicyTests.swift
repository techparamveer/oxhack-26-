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
            ("/explore/", .explore),
            ("/explore", .explore),
            ("/explore/people/", .explore),
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
            ("/explore/?q=reels", .explore),
            ("https://www.instagram.com/explore/", .explore),
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
        for mode in Mode.allCases {
            let blocked = Policy.defaultBlocked(in: mode)
            for app in WrappedApp.allCases {
                for section in Policy.sections(of: app) {
                    let expected = !blocked.contains(section)
                    XCTAssertEqual(Policy.isAllowed(section: section, mode: mode, defaults: defaults), expected, "\(mode) \(app) \(section)")
                }
            }
        }
    }

    func testIsAllowedByPath() {
        let table: [(WrappedApp, String, Mode, Bool)] = [
            (.instagram, "/", .focus, true),
            (.instagram, "/explore/", .focus, false),
            (.instagram, "/reels/", .focus, false),
            (.instagram, "/reel/Cx1/", .focus, false),
            (.instagram, "/direct/inbox/", .focus, false),
            (.instagram, "/direct/t/123", .focus, false),
            (.youtube, "/", .focus, true),
            (.youtube, "/watch?v=abc", .focus, true),
            (.youtube, "/shorts/abc", .focus, false),
            (.instagram, "/reels/", .rest, true),
            (.instagram, "/direct/inbox/", .rest, true),
            (.instagram, "/explore/", .rest, true),
            (.youtube, "/shorts/abc", .rest, true),
            (.instagram, "/reels/", .play, true),
            (.instagram, "/direct/inbox/", .play, true),
            (.youtube, "/shorts/abc", .play, true),
            (.instagram, "/reels/", .idle, true),
            (.instagram, "/explore/", .idle, true),
            (.youtube, "/shorts/abc", .idle, true),
        ]
        for (app, path, mode, expected) in table {
            XCTAssertEqual(Policy.isAllowed(app: app, path: path, mode: mode, defaults: defaults), expected, "\(app) \(path) \(mode)")
        }
    }

    func testBlockedSections() {
        XCTAssertEqual(Policy.blockedSections(app: .instagram, mode: .focus, defaults: defaults), [.reels, .explore, .dms])
        XCTAssertEqual(Policy.blockedSections(app: .youtube, mode: .focus, defaults: defaults), [.shorts])
        for mode in [Mode.rest, .play, .idle] {
            for app in WrappedApp.allCases { XCTAssertTrue(Policy.blockedSections(app: app, mode: mode, defaults: defaults).isEmpty) }
        }
    }

    // MARK: Per-mode settings

    func testDefaultBlockedPerMode() {
        XCTAssertEqual(Policy.blockedKey(for: .focus), "sheep.blockedInFocus")
        XCTAssertEqual(Policy.blockedKey(for: .rest), "sheep.blockedInRest")
        XCTAssertEqual(Policy.blockedKey(for: .play), "sheep.blockedInPlay")
        XCTAssertNil(Policy.blockedKey(for: .idle))

        XCTAssertEqual(Policy.defaultBlocked(in: .focus), [.reels, .dms, .shorts, .explore])
        XCTAssertTrue(Policy.defaultBlocked(in: .rest).isEmpty)
        XCTAssertTrue(Policy.defaultBlocked(in: .play).isEmpty)
        XCTAssertTrue(Policy.defaultBlocked(in: .idle).isEmpty)

        XCTAssertEqual(Policy.blockedSections(in: .focus, defaults: defaults), [.reels, .dms, .shorts, .explore])
        XCTAssertTrue(Policy.blockedSections(in: .rest, defaults: defaults).isEmpty)
        XCTAssertTrue(Policy.blockedSections(in: .play, defaults: defaults).isEmpty)
        XCTAssertTrue(Policy.blockedSections(in: .idle, defaults: defaults).isEmpty)
        XCTAssertFalse(Policy.isAllowed(app: .instagram, path: "/direct/inbox/", mode: .focus, defaults: defaults))
        XCTAssertTrue(Policy.isAllowed(app: .instagram, path: "/direct/inbox/", mode: .rest, defaults: defaults),
                      "Rest keeps DMs open")
    }

    func testRestDefaultsHideNothingAndHonourSaved() {
        XCTAssertEqual(Policy.defaultBlocked(in: .rest), Policy.defaultBlocked(in: .play))
        XCTAssertTrue(Policy.isAllowed(app: .instagram, path: "/reels/", mode: .rest, defaults: defaults))
        XCTAssertTrue(Policy.isAllowed(app: .youtube, path: "/shorts/abc", mode: .rest, defaults: defaults))

        Policy.setBlocked([.reels, .shorts], in: .rest, defaults: defaults)
        XCTAssertEqual(Policy.blockedSections(in: .rest, defaults: defaults), [.reels, .shorts])
        XCTAssertFalse(Policy.isAllowed(app: .instagram, path: "/reels/", mode: .rest, defaults: defaults))
        XCTAssertFalse(Policy.isAllowed(app: .youtube, path: "/shorts/abc", mode: .rest, defaults: defaults))
    }

    func testOldFocusKeyWithoutExploreStaysCompatible() {
        defaults.set(["reels", "dms", "shorts"], forKey: "sheep.blockedInFocus")
        XCTAssertEqual(Policy.blockedSections(in: .focus, defaults: defaults), [.reels, .dms, .shorts])
        XCTAssertTrue(Policy.isAllowed(app: .instagram, path: "/explore/", mode: .focus, defaults: defaults),
                      "existing installs without explore keep it open")
        XCTAssertEqual(Policy.blockedInFocusKey, "sheep.blockedInFocus")
    }

    func testBlockedInFocusSettingDrivesPolicy() {
        Policy.setBlockedInFocus([.reels], defaults: defaults)
        XCTAssertEqual(defaults.array(forKey: "sheep.blockedInFocus") as? [String], ["reels"])
        XCTAssertFalse(Policy.isAllowed(app: .instagram, path: "/reels/", mode: .focus, defaults: defaults))
        XCTAssertTrue(Policy.isAllowed(app: .instagram, path: "/direct/inbox/", mode: .focus, defaults: defaults))
        XCTAssertTrue(Policy.isAllowed(app: .instagram, path: "/explore/", mode: .focus, defaults: defaults))
        XCTAssertTrue(Policy.isAllowed(app: .youtube, path: "/shorts/abc", mode: .focus, defaults: defaults))
        XCTAssertEqual(Policy.hidingCSS(app: .youtube, mode: .focus, defaults: defaults), "")
        XCTAssertFalse(Policy.hidingCSS(app: .instagram, mode: .focus, defaults: defaults).contains("/direct/"))

        Policy.setBlockedInFocus([], defaults: defaults)
        XCTAssertTrue(Policy.blockedSections(in: .focus, defaults: defaults).isEmpty)

        defaults.set(["feed", "shorts", "bogus"], forKey: Policy.blockedInFocusKey)
        XCTAssertEqual(Policy.blockedSections(in: .focus, defaults: defaults), [.shorts], "feed is never blocked")
        XCTAssertTrue(Policy.isAllowed(app: .youtube, path: "/", mode: .focus, defaults: defaults))
    }

    func testPerModeTogglesPersistAndRoundTrip() {
        Policy.setBlocked([.reels, .explore], in: .focus, defaults: defaults)
        Policy.setBlocked([.shorts], in: .rest, defaults: defaults)
        Policy.setBlocked([.dms], in: .play, defaults: defaults)
        Policy.setBlocked([.reels], in: .idle, defaults: defaults)

        XCTAssertEqual(defaults.array(forKey: "sheep.blockedInFocus") as? [String], ["explore", "reels"])
        XCTAssertEqual(defaults.array(forKey: "sheep.blockedInRest") as? [String], ["shorts"])
        XCTAssertEqual(defaults.array(forKey: "sheep.blockedInPlay") as? [String], ["dms"])
        XCTAssertNil(defaults.object(forKey: "sheep.blockedInIdle"))

        XCTAssertEqual(Policy.blockedSections(in: .focus, defaults: defaults), [.reels, .explore])
        XCTAssertEqual(Policy.blockedSections(in: .rest, defaults: defaults), [.shorts])
        XCTAssertEqual(Policy.blockedSections(in: .play, defaults: defaults), [.dms])
        XCTAssertTrue(Policy.blockedSections(in: .idle, defaults: defaults).isEmpty)

        Policy.setBlocked([.feed, .reels], in: .rest, defaults: defaults)
        XCTAssertEqual(Policy.blockedSections(in: .rest, defaults: defaults), [.reels], "feed is never stored")
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
        XCTAssertTrue(ig.contains(#"a[href^="/explore/"]"#))
        XCTAssertTrue(ig.contains(#"a[href*="/explore/"]"#))
        XCTAssertTrue(ig.contains("display: none !important"))
        XCTAssertFalse(ig.contains("shorts"))

        let restIG = Policy.hidingCSS(app: .instagram, mode: .rest, defaults: defaults)
        XCTAssertEqual(restIG, "", "Rest hides nothing by default")
        XCTAssertFalse(restIG.contains("/explore/"), "explore hidden in Focus only")
        XCTAssertFalse(restIG.contains("/direct/"))

        let playIG = Policy.hidingCSS(app: .instagram, mode: .play, defaults: defaults)
        XCTAssertFalse(playIG.contains("/explore/"))

        let yt = Policy.hidingCSS(app: .youtube, mode: .focus, defaults: defaults)
        XCTAssertTrue(yt.contains(#"a[href*="/shorts"]"#))
        XCTAssertTrue(yt.contains("ytm-reel-shelf-renderer"))
        XCTAssertTrue(yt.contains("ytm-shorts-lockup-view-model"))
        XCTAssertFalse(yt.contains("/direct/"))
        // One rule per selector.
        XCTAssertEqual(yt.components(separatedBy: "\n").count, Policy.hidingSelectors(app: .youtube, section: .shorts).count)
    }

    func testAppsCaptionsRestAndPlay() {
        let allowed: (WrappedApp, String, Mode) -> Bool = { [defaults] app, path, mode in
            Policy.isAllowed(app: app, path: path, mode: mode, defaults: defaults)
        }
        XCTAssertEqual(AppsCaption.wrapped(app: .instagram, mode: .rest, isAllowed: allowed), "Everything open in Rest")
        XCTAssertEqual(AppsCaption.wrapped(app: .youtube, mode: .rest, isAllowed: allowed), "Everything open in Rest")
        XCTAssertEqual(AppsCaption.wrapped(app: .instagram, mode: .play, isAllowed: allowed), "Everything open in Play")
        XCTAssertEqual(AppsCaption.wrapped(app: .youtube, mode: .play, isAllowed: allowed), "Everything open in Play")
        XCTAssertEqual(AppsCaption.wrapped(app: .instagram, mode: .focus, isAllowed: allowed),
                       "Reels, Explore and DMs hidden")
    }

    func testBlockedCopyReadsNaturally() {
        XCTAssertEqual(BlockedCopy.sectionNote(section: .reels, mode: .rest), "Reels are off while you rest")
        XCTAssertEqual(BlockedCopy.sectionNote(section: .explore, mode: .focus), "Explore is off while you focus")
        XCTAssertEqual(BlockedCopy.sectionNote(section: .dms, mode: .focus), "messages are off while you focus")
        XCTAssertEqual(BlockedCopy.backTitle(mode: .rest), "Back to rest")
        XCTAssertEqual(BlockedCopy.backTitle(mode: .focus), "Back to focus")
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
