// 테스트는 컴파일타임 보장 픽스처에 한해 강제 언래핑 허용 (CODE_REVIEW.md §4)
// swiftlint:disable force_unwrapping
import Foundation
import Testing
@testable import FOMOCore

struct PriceRangeStatsTests {
    /// 종가만 의미 있는 봉. 저가·고가는 일부러 종가 밖으로 벌려 "꼬리는 무시"를 함께 검증한다.
    private func candle(close: Double, open: Double? = nil) -> Candle {
        Candle(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60),
               open: open ?? close, high: close * 1.5, low: close * 0.5, close: close)
    }

    @Test func 범위는_종가_기준이고_꼬리는_무시() {
        let stats = PriceRangeStats(candles: [candle(close: 100), candle(close: 200)], current: 190)!
        #expect(stats.low == 100)
        #expect(stats.high == 200)
    }

    @Test func 현재가가_범위_위쪽이면_high_구간() {
        let stats = PriceRangeStats(candles: [candle(close: 100), candle(close: 200)], current: 190)!
        #expect(abs(stats.position - 0.9) < 0.0001)
        #expect(stats.zone == .high)
    }

    @Test func 현재가가_범위_아래쪽이면_low_구간() {
        let stats = PriceRangeStats(candles: [candle(close: 100), candle(close: 200)], current: 110)!
        #expect(stats.zone == .low)
    }

    @Test func 현재가가_가운데면_mid_구간() {
        let stats = PriceRangeStats(candles: [candle(close: 100), candle(close: 200)], current: 150)!
        #expect(stats.zone == .mid)
    }

    @Test func 현재가가_범위를_넘으면_범위를_넓힌다() {
        let stats = PriceRangeStats(candles: [candle(close: 100), candle(close: 200)], current: 220)!
        #expect(stats.high == 220)
        #expect(stats.position == 1)
    }

    @Test func 등락률은_기간_시작가_기준() {
        let stats = PriceRangeStats(candles: [candle(close: 120, open: 100), candle(close: 130)], current: 110)!
        #expect(abs(stats.changePct - 10) < 0.0001)
    }

    @Test func 봉이_없으면_nil() {
        #expect(PriceRangeStats(candles: [], current: 100) == nil)
    }

    @Test func 최저와_최고가_같으면_가운데로_본다() {
        let stats = PriceRangeStats(candles: [candle(close: 100)], current: 100)!
        #expect(stats.position == 0.5)
    }
}

struct ChartRangeTests {
    @Test func 기간별_점_개수는_훑기에_적당한_범위() {
        // 실시간은 1분봉 5개로 시작해 1초 점을 이어 붙이므로 제외
        for range in ChartRange.allCases where range != .live {
            let count = Int(range.duration / range.intervalSeconds)
            #expect((150...300).contains(count), "\(range) 점 개수 \(count)")
        }
    }

    @Test func 실시간은_최근_5분을_1분봉으로() {
        #expect(ChartRange.live.duration == 300)
        #expect(ChartRange.live.interval == "1m")
        #expect(!ChartRange.live.showsSessionBands)
    }

    @Test func 점으로_계산해도_봉과_같은_결과() {
        let stats = PriceRangeStats(closes: [100, 200, 150], open: 100, current: 150)!
        #expect(stats.low == 100)
        #expect(stats.high == 200)
        #expect(stats.position == 0.5)
        #expect(abs(stats.changePct - 50) < 0.0001)
    }

    @Test func 정규장_띠는_1일과_1주에만() {
        #expect(ChartRange.day.showsSessionBands)
        #expect(ChartRange.week.showsSessionBands)
        #expect(!ChartRange.month.showsSessionBands)
        #expect(!ChartRange.quarter.showsSessionBands)
    }

    @Test func 종목별_본시장() {
        #expect(MarketSession.marketID(forTicker: "NVDA") == "us")
        #expect(MarketSession.marketID(forTicker: "SMSN") == "kr")
        #expect(MarketSession.marketID(forTicker: "KIOXIA") == "jp")
    }
}

@MainActor
struct RegularIntervalTests {
    let us = MarketSession.defaults.first { $0.id == "us" }!

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        return us.marketCalendar.date(from: comps)!
    }

    @Test func 평일_이틀이면_정규장_구간_두_개() {
        // 2026-08-05(수) 00:00 ~ 08-07(금) 00:00
        let intervals = us.regularIntervals(from: date(2026, 8, 5, 0, 0), to: date(2026, 8, 7, 0, 0),
                                            cal: us.marketCalendar)
        #expect(intervals.count == 2)
        #expect(intervals.first?.start == date(2026, 8, 5, 9, 30))
        #expect(intervals.first?.end == date(2026, 8, 5, 16, 0))
    }

    @Test func 주말과_휴장일은_제외() {
        // 2026-08-08(토)~08-10(월) 00:00 → 없음, 12-25 성탄절 → 없음
        #expect(us.regularIntervals(from: date(2026, 8, 8, 0, 0), to: date(2026, 8, 10, 0, 0),
                                    cal: us.marketCalendar).isEmpty)
        #expect(us.regularIntervals(from: date(2026, 12, 25, 0, 0), to: date(2026, 12, 26, 0, 0),
                                    cal: us.marketCalendar).isEmpty)
    }

    @Test func 구간_경계에서_잘라낸다() {
        // 장중 11:00에 시작하면 첫 구간은 11:00부터
        let intervals = us.regularIntervals(from: date(2026, 8, 5, 11, 0), to: date(2026, 8, 5, 15, 0),
                                            cal: us.marketCalendar)
        #expect(intervals == [DateInterval(start: date(2026, 8, 5, 11, 0), end: date(2026, 8, 5, 15, 0))])
    }
}
// swiftlint:enable force_unwrapping
