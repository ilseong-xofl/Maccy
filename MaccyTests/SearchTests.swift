import XCTest
import Defaults
@testable import Maccy

@MainActor
class SearchTests: XCTestCase {
  let savedSearchMode = Defaults[.searchMode]
  let savedShowSpecialSymbols = Defaults[.showSpecialSymbols]
  let savedHighlightMatch = Defaults[.highlightMatch]
  var items: [Search.Searchable]!

  override func tearDown() {
    super.tearDown()
    Defaults[.searchMode] = savedSearchMode
    Defaults[.showSpecialSymbols] = savedShowSpecialSymbols
    Defaults[.highlightMatch] = savedHighlightMatch
  }

  func testSimpleSearch() { // swiftlint:disable:this function_body_length
    Defaults[.searchMode] = Search.Mode.exact
    items = [
      HistoryItemDecorator(historyItemWithTitle("foo bar baz")),
      HistoryItemDecorator(historyItemWithTitle("foo bar zaz")),
      HistoryItemDecorator(historyItemWithTitle("xxx yyy zzz"))
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], ranges: []),
      Search.SearchResult(score: nil, object: items[1], ranges: []),
      Search.SearchResult(score: nil, object: items[2], ranges: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(
        score: nil,
        object: items[0],
        ranges: [range(from: 10, to: 10, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 8, to: 8, in: items[1])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 8, to: 8, in: items[2])]
      )
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(
        score: nil,
        object: items[0],
        ranges: [range(from: 0, to: 2, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 0, to: 2, in: items[1])]
      )
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 8, to: 9, in: items[1])]
      )
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 4, to: 6, in: items[2])]
      )
    ])
    XCTAssertEqual(search("fbb"), [])
    XCTAssertEqual(search("m"), [])
  }

  func testFuzzySearch() { // swiftlint:disable:this function_body_length
    Defaults[.searchMode] = Search.Mode.fuzzy
    items = [
      HistoryItemDecorator(historyItemWithTitle("foo bar baz")),
      HistoryItemDecorator(historyItemWithTitle("foo bar zaz")),
      HistoryItemDecorator(historyItemWithTitle("xxx yyy zzz"))
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], ranges: []),
      Search.SearchResult(score: nil, object: items[1], ranges: []),
      Search.SearchResult(score: nil, object: items[2], ranges: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(
        score: 0.08,
        object: items[1],
        ranges: [range(from: 8, to: 8, in: items[1]), range(from: 10, to: 10, in: items[1])]
      ),
      Search.SearchResult(
        score: 0.08,
        object: items[2],
        ranges: [range(from: 8, to: 10, in: items[2])]
      ),
      Search.SearchResult(
        score: 0.1,
        object: items[0],
        ranges: [range(from: 10, to: 10, in: items[0])]
      )
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(
        score: 0.0,
        object: items[0],
        ranges: [range(from: 0, to: 2, in: items[0])]
      ),
      Search.SearchResult(
        score: 0.0,
        object: items[1],
        ranges: [range(from: 0, to: 2, in: items[1])]
      )
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(
        score: 0.08,
        object: items[1],
        ranges: [range(from: 5, to: 5, in: items[1]), range(from: 8, to: 9, in: items[1])]
      ),
      Search.SearchResult(
        score: 0.54,
        object: items[0],
        ranges: [range(from: 5, to: 5, in: items[0]), range(from: 9, to: 10, in: items[0])]
      ),
      Search.SearchResult(
        score: 0.58,
        object: items[2],
        ranges: [range(from: 8, to: 10, in: items[2])]
      )
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(
        score: 0.04,
        object: items[2],
        ranges: [range(from: 4, to: 6, in: items[2])]
      )
    ])
    XCTAssertEqual(search("fbb"), [
      Search.SearchResult(
        score: 0.6666666666666666,
        object: items[0],
        ranges: [
          range(from: 0, to: 0, in: items[0]),
          range(from: 4, to: 4, in: items[0]),
          range(from: 8, to: 8, in: items[0])
        ]
      ),
      Search.SearchResult(
        score: 0.6666666666666666,
        object: items[1],
        ranges: [range(from: 0, to: 0, in: items[1]), range(from: 4, to: 4, in: items[1])])
    ])
    XCTAssertEqual(search("m"), [])
  }

  func testRegexpSearch() { // swiftlint:disable:this function_body_length
    Defaults[.searchMode] = Search.Mode.regexp
    items = [
      HistoryItemDecorator(historyItemWithTitle("foo bar baz")),
      HistoryItemDecorator(historyItemWithTitle("foo bar zaz")),
      HistoryItemDecorator(historyItemWithTitle("xxx yyy zzz"))
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], ranges: []),
      Search.SearchResult(score: nil, object: items[1], ranges: []),
      Search.SearchResult(score: nil, object: items[2], ranges: [])
    ])
    XCTAssertEqual(search("z+"), [
      Search.SearchResult(
        score: nil,
        object: items[0],
        ranges: [range(from: 10, to: 10, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 8, to: 8, in: items[1])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 8, to: 10, in: items[2])]
      )
    ])
    XCTAssertEqual(search("z*"), [
      Search.SearchResult(
        score: nil,
        object: items[0],
        ranges: [range(from: 0, to: -1, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 0, to: -1, in: items[1])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 0, to: -1, in: items[2])]
      )
    ])
    XCTAssertEqual(search("^foo"), [
      Search.SearchResult(
        score: nil,
        object: items[0], ranges: [range(from: 0, to: 2, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1], ranges: [range(from: 0, to: 2, in: items[1])]
      )
    ])
    XCTAssertEqual(search(" za"), [
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 7, to: 9, in: items[1])]
      )
    ])
    XCTAssertEqual(search("[y]+"), [
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 4, to: 6, in: items[2])]
      )
    ])
    XCTAssertEqual(search("fbb"), [])
    XCTAssertEqual(search("m"), [])
  }

  func testSearchHighlightsUnicodeOnSecondLine() throws {
    Defaults[.searchMode] = .exact
    Defaults[.showSpecialSymbols] = true
    Defaults[.highlightMatch] = .bold
    let source = "👨‍👩‍👧‍👦 첫째\r\n\u{FFFC}둘째 café 검색"
    let item = HistoryItemDecorator(historyItemWithTitle(source))
    items = [item]

    let result = try XCTUnwrap(search("café 검색").first)
    XCTAssertEqual(result.ranges.count, 1)
    let match = try XCTUnwrap(result.ranges.first)
    XCTAssertEqual(String(item.listText[match]), "café 검색")
    item.highlight("café 검색", result.ranges)

    var expected = AttributedString("👨‍👩‍👧‍👦 첫째\n둘째 café 검색")
    expected[try XCTUnwrap(expected.range(of: "café 검색"))].font = .bold(.body)()
    XCTAssertEqual(item.attributedTitle, expected)
    XCTAssertEqual(item.item.text, source)
  }

  func testExactAndRegexpSearchMatchPreservedNewlines() throws {
    Defaults[.showSpecialSymbols] = true
    let item = HistoryItemDecorator(historyItemWithTitle("first\nsecond"))
    items = [item]

    for mode in [Search.Mode.exact, .regexp, .mixed] {
      Defaults[.searchMode] = mode
      let result = try XCTUnwrap(search("first\nsecond").first, "Mode: \(mode)")
      let match = try XCTUnwrap(result.ranges.first)
      XCTAssertEqual(String(item.listText[match]), "first\nsecond")
    }
  }

  func testFuzzySearchRangesUseMultilineListText() throws {
    Defaults[.searchMode] = .fuzzy
    Defaults[.showSpecialSymbols] = true
    let item = HistoryItemDecorator(historyItemWithTitle("first\nsecond"))
    items = [item]

    let result = try XCTUnwrap(search("second").first)
    XCTAssertFalse(result.ranges.isEmpty)
    XCTAssertTrue(result.ranges.contains { String(item.listText[$0]) == "second" })
  }

  func testSearchIncludesTextBeyondGeneratedTitleLimit() throws {
    Defaults[.searchMode] = .exact
    let source = String(repeating: "a", count: 1_100) + "\nUnique needle"
    let item = HistoryItemDecorator(historyItemWithTitle(source))
    items = [item]

    XCTAssertFalse(item.title.contains("Unique needle"))
    let result = try XCTUnwrap(search("Unique needle").first)
    let match = try XCTUnwrap(result.ranges.first)
    XCTAssertEqual(String(item.listText[match]), "Unique needle")
  }

  func testSearchMatchesDisplayedCustomAlias() throws {
    Defaults[.searchMode] = .exact
    let historyItem = historyItemWithTitle("Copied text\nSecond line")
    historyItem.title = "Personal alias"
    let item = HistoryItemDecorator(historyItem)
    items = [item]

    let result = try XCTUnwrap(search("Personal").first)
    let match = try XCTUnwrap(result.ranges.first)
    XCTAssertEqual(String(item.listText[match]), "Personal")
    XCTAssertEqual(search("Second line"), [])
  }

  private func search(_ string: String) -> [Search.SearchResult] {
    return Search().search(string: string, within: items)
  }

  // swiftlint:disable:next identifier_name
  private func range(from: Int, to: Int, in item: HistoryItemDecorator) -> Range<String.Index> {
    let startIndex = item.listText.startIndex
    let lowerBound = item.listText.index(startIndex, offsetBy: from)
    let upperBound = item.listText.index(startIndex, offsetBy: to + 1)

    return lowerBound..<upperBound
  }

  private func historyItemWithTitle(_ value: String?) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value?.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()

    return item
  }
}
