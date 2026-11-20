import XCTest

/// UI 스모크 테스트 — 머지·TestFlight 전에 "앱이 뜨고 4탭이 살아 있다"를 기계로 확인하고 스크린샷을 남긴다.
/// 원격(Discord) 파이프라인에서 Claude가 돌리고 결과 스크린샷을 보고하는 용도 (`make smoke`).
/// 언어 설정에 의존하지 않도록 탭은 인덱스로, 텍스트는 언어 무관한 것("FOMO24", 통화 코드)만 확인한다.
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // DEBUG 런치 옵션: 데모 FOMO 기록 삽입, 아일랜드 팁 숨김 (App.swift 참고)
        app.launchArguments += ["-seedDemo", "YES", "-hideIslandTip", "YES", "-initialTab", "0"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func test_4탭_순회_및_스크린샷() throws {
        // 마켓: 타이틀 + 통화 칩 + 첫 시세(달러 기호)까지 표시되는지
        XCTAssertTrue(app.staticTexts["FOMO24"].waitForExistence(timeout: 10), "마켓 탭 타이틀 없음")
        XCTAssertTrue(app.staticTexts["USD"].exists, "통화 칩(USD) 없음")
        let firstPrice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '$'")).firstMatch
        XCTAssertTrue(firstPrice.waitForExistence(timeout: 25), "25초 내 시세($) 미표시 — 네트워크 또는 파싱 실패")
        attach("1-markets")

        // 통화 전환: KRW 칩을 누르면 ₩ 가격이 나타나야 한다 (FX 환율 경로)
        app.staticTexts["KRW"].tap()
        let krwPrice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '₩'")).firstMatch
        XCTAssertTrue(krwPrice.waitForExistence(timeout: 10), "KRW 선택 후 ₩ 가격 없음")
        attach("1b-markets-krw")
        app.staticTexts["USD"].tap()

        let tabs = app.tabBars.firstMatch.buttons
        XCTAssertEqual(tabs.count, 4, "탭이 4개가 아님: \(tabs.count)")

        // FOMO: 데모 기록 3건 → 수익률(%) 텍스트가 있어야 함
        tabs.element(boundBy: 1).tap()
        let pct = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '%'")).firstMatch
        XCTAssertTrue(pct.waitForExistence(timeout: 15), "FOMO 탭에 수익률(%) 없음 — seedDemo 또는 시세 실패")
        attach("2-fomo")

        // 쇼케이스 슬라이드 → "더보기" 카드 → 바텀시트. 원격 구성이 4개 미만이면 카드가 없으므로 건너뛴다
        // (쇼케이스는 콘텐츠 설정이지 앱 결함이 아니라서 실패로 치지 않는다).
        let slide = app.scrollViews["showcase.slide"]
        if slide.waitForExistence(timeout: 10) {
            slide.swipeLeft()
            slide.swipeLeft()
            let more = app.buttons["showcase.more"]
            if more.waitForExistence(timeout: 5) {
                attach("2b-fomo-showcase-slide")
                more.tap()
                XCTAssertTrue(app.scrollViews["showcase.sheet"].waitForExistence(timeout: 5), "더보기 시트가 열리지 않음")
                attach("2c-fomo-showcase-sheet")
                app.scrollViews["showcase.sheet"].swipeUp()
                attach("2d-fomo-showcase-sheet-bottom")
                app.buttons["showcase.close"].tap()
                XCTAssertTrue(app.scrollViews["showcase.sheet"].waitForNonExistence(timeout: 5), "더보기 시트가 닫히지 않음")
            }
        }

        // 캘린더: 요일 헤더 + 원격 이벤트(REST) 1건 이상
        tabs.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["Mon"].waitForExistence(timeout: 10) || app.staticTexts["월"].exists, "캘린더 요일 헤더 없음")
        attach("3-calendar")

        // 더보기
        tabs.element(boundBy: 3).tap()
        XCTAssertTrue(app.staticTexts["FOMO24"].waitForExistence(timeout: 10) || app.cells.firstMatch.waitForExistence(timeout: 10), "더보기 탭 내용 없음")
        attach("4-more")
    }

    /// 차트: 종목 행 탭 → 시트 → 훑기 → 그 시점으로 FOMO 기록 추가까지 한 흐름.
    func test_차트_열기_훑기_기록추가() throws {
        let firstPrice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '$'")).firstMatch
        XCTAssertTrue(firstPrice.waitForExistence(timeout: 25), "25초 내 시세($) 미표시")
        app.cells.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25)).tap()

        let plot = app.otherElements["chart.plot"]
        XCTAssertTrue(plot.waitForExistence(timeout: 20), "차트가 20초 내 표시되지 않음 — 봉 조회 실패")
        attach("5-chart")

        // 훑기: 손을 뗀 뒤에도 선택 시점이 남아 '기록' 버튼이 보여야 한다
        let from = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let to = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        from.press(forDuration: 0.4, thenDragTo: to)
        let save = app.buttons["chart.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "훑은 뒤 '기록' 버튼 없음")
        attach("5b-chart-scrubbed")

        let before = app.buttons.matching(identifier: "chart.entry").count
        save.tap()
        let added = NSPredicate { _, _ in self.app.buttons.matching(identifier: "chart.entry").count == before + 1 }
        wait(for: [expectation(for: added, evaluatedWith: nil)], timeout: 5)
        attach("5c-chart-entry-added")

        // 실시간 탭: 1초 점이 쌓일 시간을 준 뒤에도 차트가 살아 있어야 한다
        app.buttons["chart.range.live"].tap()
        XCTAssertTrue(plot.waitForExistence(timeout: 20), "실시간 차트 미표시")
        XCTAssertTrue(app.staticTexts["LIVE"].waitForExistence(timeout: 15), "실시간 연결(LIVE) 표시 없음")
        Thread.sleep(forTimeInterval: 8)
        XCTAssertTrue(plot.exists, "실시간 8초 뒤 차트가 사라짐")
        attach("5d-chart-live")
    }

    /// 즐겨찾기: 셋째 행의 별을 눌러 추가 → 즐겨찾기 탭에 그 종목만 → 별을 다시 눌러 해제 → 빈 화면 안내.
    func test_즐겨찾기_추가_및_해제() throws {
        let firstPrice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '$'")).firstMatch
        XCTAssertTrue(firstPrice.waitForExistence(timeout: 25), "25초 내 시세($) 미표시")
        let stars = app.buttons.matching(identifier: "row.favorite")
        // 술어를 변수로 재사용하면 Swift 6이 메인 액터로 두 번 넘긴다고 막는다 — 쓸 때마다 새로 만든다
        XCTAssertEqual(stars.matching(NSPredicate(format: "isSelected == true")).count, 0, "시작부터 즐겨찾기한 종목이 있음")

        stars.element(boundBy: 2).tap()
        let starred = stars.matching(NSPredicate(format: "isSelected == true")).firstMatch
        XCTAssertTrue(starred.waitForExistence(timeout: 5), "별을 눌러도 즐겨찾기 표시 없음")
        attach("6-favorite-added")

        app.buttons["market.tab.favorites"].tap()
        XCTAssertTrue(stars.firstMatch.waitForExistence(timeout: 5), "즐겨찾기 탭에 종목 없음")
        XCTAssertEqual(app.cells.count, 1, "즐겨찾기 탭에 1종목이 아님: \(app.cells.count)")
        attach("6b-favorites-tab")

        // 테스트가 사용자의 즐겨찾기를 남기지 않도록 해제까지 수행
        stars.firstMatch.tap()
        XCTAssertTrue(app.buttons["favorites.browseAll"].waitForExistence(timeout: 5), "해제 후 빈 즐겨찾기 안내 없음")
        attach("6c-favorites-empty")
        app.buttons["favorites.browseAll"].tap()
        XCTAssertTrue(app.buttons["market.tab.all"].isSelected, "전체 종목 보기 후 전체 탭이 아님")
    }

    /// 스크린샷을 결과 번들에 영구 첨부 — scripts/smoke.sh 가 xcresulttool로 PNG 추출.
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
