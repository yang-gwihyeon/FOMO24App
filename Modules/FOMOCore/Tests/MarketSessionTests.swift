import Foundation
import Testing
@testable import FOMOCore

@MainActor
struct MarketSessionTests {
    let us = MarketSession.defaults.first { $0.id == "us" }!
    let kr = MarketSession.defaults.first { $0.id == "kr" }!

    /// 특정 시장 시간대의 (y, m, d, h, m) → Date
    private func date(_ session: MarketSession, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        return MarketSession.calendar(for: session.timeZoneID).date(from: comps)!
    }

    @Test func 미국_정규장_중에는_regular() {
        // 2026-08-05는 수요일 (휴장일 아님)
        let now = date(us, 2026, 8, 5, 10, 0)   // 뉴욕 10:00
        #expect(us.status(at: now).phase == .regular)
    }

    @Test func 미국_프리마켓은_preMarket() {
        let now = date(us, 2026, 8, 5, 5, 0)    // 뉴욕 05:00
        #expect(us.status(at: now).phase == .preMarket)
    }

    @Test func 주말은_weekend() {
        // 2026-08-08은 토요일
        let now = date(us, 2026, 8, 8, 12, 0)
        #expect(us.status(at: now).phase == .weekend)
    }

    @Test func 휴장일은_holiday() {
        // 12-25 성탄절 (금요일, 2026)
        let now = date(us, 2026, 12, 25, 12, 0)
        #expect(us.status(at: now).phase == .holiday("성탄절"))
    }

    @Test func 한국_정규장_마감후_애프터마켓은_afterHours() {
        let now = date(kr, 2026, 8, 5, 16, 0)   // 서울 16:00 → NXT 애프터
        #expect(kr.status(at: now).phase == .afterHours)
    }

    @Test func 다음_개장은_주말을_건너뛴다() {
        // 금요일 장 마감 후 → 다음 개장은 월요일이어야 함
        let fridayNight = date(us, 2026, 8, 7, 21, 0)
        let status = us.status(at: fridayNight)
        let cal = MarketSession.calendar(for: us.timeZoneID)
        let weekday = cal.component(.weekday, from: status.nextChange)
        #expect(weekday == 2)   // 월요일
    }

    @Test func 개장예정_목록은_휴장일을_제외한다() {
        // 성탄절 직전 → 예정 개장 목록에 12/25가 없어야 함
        let now = date(us, 2026, 12, 23, 18, 0)
        let cal = MarketSession.calendar(for: us.timeZoneID)
        let opens = us.upcomingRegularOpens(count: 5, from: now)
        #expect(!opens.isEmpty)
        for open in opens {
            let c = cal.dateComponents([.month, .day], from: open)
            #expect(!(c.month == 12 && c.day == 25))
        }
    }

    @Test func 원격파싱_정상데이터() {
        let remote: [String: Any] = [
            "id": "us", "name": "미국", "flag": "🇺🇸", "timeZoneID": "America/New_York",
            "windows": [["kind": "regular", "open": "09:30", "close": "16:00"]],
            "holidays": ["12-25": "성탄절"],
        ]
        let session = MarketSession(remote: remote)
        #expect(session != nil)
        #expect(session?.regular.open.h == 9)
        #expect(session?.regular.open.m == 30)
        #expect(session?.holidays["12-25"] == "성탄절")
    }

    @Test func 원격파싱_정규장없으면_nil() {
        let remote: [String: Any] = [
            "id": "x", "name": "X", "flag": "🏳️", "timeZoneID": "UTC",
            "windows": [["kind": "pre", "open": "08:00", "close": "09:00"]],
        ]
        #expect(MarketSession(remote: remote) == nil)
    }

    @Test func 원격파싱_잘못된_시각형식은_무시() {
        let remote: [String: Any] = [
            "id": "x", "name": "X", "flag": "🏳️", "timeZoneID": "UTC",
            "windows": [
                ["kind": "regular", "open": "25:00", "close": "16:00"],   // 잘못된 시각
            ],
        ]
        #expect(MarketSession(remote: remote) == nil)
    }
}
