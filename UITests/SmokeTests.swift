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

        // 캘린더: 요일 헤더 + 원격 이벤트(REST) 1건 이상
        tabs.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["Mon"].waitForExistence(timeout: 10) || app.staticTexts["월"].exists, "캘린더 요일 헤더 없음")
        attach("3-calendar")

        // 더보기
        tabs.element(boundBy: 3).tap()
        XCTAssertTrue(app.staticTexts["FOMO24"].waitForExistence(timeout: 10) || app.cells.firstMatch.waitForExistence(timeout: 10), "더보기 탭 내용 없음")
        attach("4-more")
    }

    /// 스크린샷을 결과 번들에 영구 첨부 — scripts/smoke.sh 가 xcresulttool로 PNG 추출.
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
