import XCTest
@testable import Sheep

final class NotebookTests: XCTestCase {
    private var originalRoot: URL!
    private var tmp: URL!

    override func setUp() {
        super.setUp()
        originalRoot = AppPaths.root
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notebook-\(UUID())", isDirectory: true)
        AppPaths.root = tmp
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        AppPaths.root = originalRoot
        super.tearDown()
    }

    private func file(_ path: String, _ content: String = "") -> MemoryFile {
        MemoryFile(path: path, content: content)
    }

    // MARK: Header parsing

    func testParsesYAMLHeaderAndHidesItFromBody() {
        let doc = MemoryDocument("""
        ---
        id: dissertation-ch3
        type: workstream
        aliases: [dissertation, "ch3"]
          - nested: ignored
        updated: "2026-10-23T22:40:00Z"
        ---

        # Dissertation ch.3
        - due Fri 30 Oct
        """)
        XCTAssertEqual(doc.id, "dissertation-ch3")
        XCTAssertEqual(doc.fields["type"], "workstream")
        XCTAssertEqual(doc.fields["aliases"], "[dissertation, \"ch3\"]")
        XCTAssertEqual(doc.updated, "2026-10-23T22:40:00Z")
        XCTAssertNil(doc.fields["nested"])
        XCTAssertEqual(doc.body, "# Dissertation ch.3\n- due Fri 30 Oct")
        XCTAssertEqual(doc.firstHeading, "Dissertation ch.3")
    }

    func testFileWithoutHeaderIsAllBody() {
        let text = "# Patterns\n- Reels ~12 min into Focus"
        let doc = MemoryDocument(text)
        XCTAssertTrue(doc.fields.isEmpty)
        XCTAssertEqual(doc.body, text)
        XCTAssertNil(doc.updated)
    }

    func testUnterminatedHeaderIsTreatedAsBody() {
        let text = "---\nid: x\nno closing fence"
        let doc = MemoryDocument(text)
        XCTAssertTrue(doc.fields.isEmpty)
        XCTAssertEqual(doc.body, text)
    }

    func testCRLFHeaderIsParsed() {
        let doc = MemoryDocument("---\r\nid: day\r\nupdated: 2026-10-23\r\n---\r\n# Day\r\n- one")
        XCTAssertEqual(doc.id, "day")
        XCTAssertEqual(doc.updated, "2026-10-23")
        XCTAssertEqual(doc.body, "# Day\n- one")
    }

    // MARK: Path safety + routing

    func testOnlyRelativeMarkdownPathsInsideMemoryRootAreSafe() {
        for ok in ["profile.md", "timeline/daily/2026-10-23.md", "workstreams/active/ch3.md"] {
            XCTAssertTrue(NotebookModel.isSafeMemoryPath(ok), ok)
        }
        for bad in ["", "/etc/passwd.md", "~/x.md", "../escape.md", "knowledge/../../escape.md",
                    "./profile.md", "a//b.md", "history/2026/profile.md", "events.jsonl", "notes.txt",
                    "..\\escape.md"] {
            XCTAssertFalse(NotebookModel.isSafeMemoryPath(bad), bad)
        }
    }

    func testOpeningAFileGoesThroughTheRouter() {
        let router = Router()
        router.push(.notebook)
        router.push(.notebookFile("profile.md"))
        XCTAssertEqual(router.path, [.notebook, .notebookFile("profile.md")])
    }

    // MARK: Titles + dates

    func testDailyTitleFormatting() {
        XCTAssertEqual(NotebookModel.dailyTitle("2026-10-23"), "Fri 23 Oct")
        XCTAssertEqual(NotebookModel.dailyTitle("2026-01-05"), "Mon 5 Jan")
        XCTAssertNil(NotebookModel.dailyTitle("notes"))
    }

    func testUpdatedFormattingIsLenient() {
        XCTAssertEqual(NotebookModel.formatUpdated("2026-10-23"), "Fri 23 Oct")
        XCTAssertEqual(NotebookModel.formatUpdated("2026-10-23T10:00:00Z"), "Fri 23 Oct")
        XCTAssertEqual(NotebookModel.formatUpdated("2026-10-23T10:00:00.123Z"), "Fri 23 Oct")
        XCTAssertEqual(NotebookModel.formatUpdated("yesterday"), "yesterday")
    }

    func testTitleDerivation() {
        func title(_ path: String, _ content: String) -> String {
            NotebookModel.title(path: path, document: MemoryDocument(content))
        }
        XCTAssertEqual(title("timeline/daily/2026-10-23.md", "# Thursday"), "Fri 23 Oct")
        XCTAssertEqual(title("knowledge/what-works.md", "# What works"), "What gets you back")
        XCTAssertEqual(title("workstreams/active/ch3.md", "---\nid: ch3-goal\n---\n# Dissertation ch.3"), "Dissertation ch.3")
        XCTAssertEqual(title("workstreams/active/ch3.md", "---\nid: dissertation-ch3\n---\njust text"), "Dissertation ch3")
        XCTAssertEqual(title("knowledge/patterns.md", "no heading"), "Patterns")
        XCTAssertEqual(title("workstreams/active/gym_plan.md", ""), "Gym plan")
    }

    // MARK: Grouping + sorting

    func testGroupingAndSorting() {
        let files = [
            file("knowledge/what-works.md"),
            file("knowledge/patterns.md"),
            file("profile.md", "---\nupdated: 2026-10-23\n---\n# You"),
            file("timeline/daily/2026-10-22.md"),
            file("timeline/daily/2026-10-23.md"),
            file("workstreams/completed/essay.md", "---\nupdated: 2026-10-20\n---\n# Essay"),
            file("workstreams/active/ch3.md", "# Dissertation ch.3"),
            file("workstreams/active/apply.md", "# Apply for internships"),
            file("misc.md"),
        ]
        let groups = NotebookModel.groups(from: files)
        XCTAssertEqual(groups.map(\.section), [.about, .days, .noticed, .goals, .other])
        XCTAssertEqual(groups[0].entries.first?.caption, "updated Fri 23 Oct")
        XCTAssertEqual(groups[1].entries.map(\.title), ["Fri 23 Oct", "Thu 22 Oct"])
        XCTAssertEqual(groups[2].entries.map(\.title), ["Patterns", "What gets you back"])
        XCTAssertEqual(groups[3].entries.map(\.title), ["Apply for internships", "Dissertation ch.3", "Essay"])
        XCTAssertEqual(groups[3].entries.last?.caption, "done · updated Tue 20 Oct")
        XCTAssertNil(groups[3].entries.first?.caption)
    }

    func testEmptySectionsAreOmitted() {
        XCTAssertTrue(NotebookModel.groups(from: []).isEmpty)
        XCTAssertEqual(NotebookModel.groups(from: [file("timeline/daily/2026-10-23.md")]).map(\.section), [.days])
    }

    // MARK: Markdown blocks

    func testMarkdownBlocks() {
        let blocks = MarkdownBlock.parse("\n# Day\n\n\n- one\n  - two\nplain\n")
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Day"), .spacer,
            .bullet(indent: 0, text: "one"), .bullet(indent: 1, text: "two"),
            .paragraph("plain"),
        ])
    }

    // MARK: Through MemoryStore

    func testWriteAndDeleteReflectedInModel() {
        let store = MemoryStore.shared
        XCTAssertTrue(NotebookModel.groups(from: store.list()).isEmpty)

        store.write("timeline/daily/2026-10-23.md", content: "---\nid: day\nupdated: 2026-10-23\n---\n# Day")
        store.write("profile.md", content: "# About you")
        var groups = NotebookModel.groups(from: store.list())
        XCTAssertEqual(groups.map(\.section), [.about, .days])
        XCTAssertEqual(groups[1].entries.first?.title, "Fri 23 Oct")

        store.write("profile.md", content: "---\nupdated: 2026-10-24\n---\n# Edited")
        groups = NotebookModel.groups(from: store.list())
        XCTAssertEqual(groups[0].entries.first?.title, "Edited")
        XCTAssertEqual(groups[0].entries.first?.caption, "updated Sat 24 Oct")

        store.delete("profile.md")
        groups = NotebookModel.groups(from: store.list())
        XCTAssertEqual(groups.map(\.section), [.days])
        XCTAssertNil(store.read("profile.md"))
    }
}
