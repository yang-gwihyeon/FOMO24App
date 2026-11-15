import Foundation
import Testing
import FOMOCore
@testable import MarketKit

struct CandleParsingTests {
    /// 실제 candleSnapshot 응답에서 두 봉을 발췌 (2026-11-15 확인).
    private let sample = """
    [{"t":1794708000000,"T":1794711599999,"s":"xyz:NVDA","i":"1h","o":"158.05","c":"160.02","h":"160.31","l":"157.95","v":"51692.527","n":9812},
     {"t":1794704400000,"T":1794707999999,"s":"xyz:NVDA","i":"1h","o":"159.58","c":"158.04","h":"159.61","l":"157.5","v":"53592.597","n":7323}]
    """

    @Test func 봉을_시간순으로_파싱() throws {
        let candles = try HyperliquidCandleService.parse(Data(sample.utf8))
        #expect(candles.count == 2)
        #expect(candles[0].start < candles[1].start)
        #expect(candles[0].open == 159.58)
        #expect(candles[0].low == 157.5)
        #expect(candles[1].close == 160.02)
        #expect(candles[1].end.timeIntervalSince1970 == 1_794_711_599.999)
    }

    @Test func 숫자가_깨진_봉은_건너뛴다() throws {
        let broken = """
        [{"t":1,"T":2,"o":"abc","c":"1","h":"1","l":"1"},
         {"t":3,"T":4,"o":"1","c":"2","h":"2","l":"1"}]
        """
        let candles = try HyperliquidCandleService.parse(Data(broken.utf8))
        #expect(candles.count == 1)
    }

    @Test func 배열이_아니면_decoding_오류() {
        #expect(throws: PriceServiceError.self) {
            _ = try HyperliquidCandleService.parse(Data("{\"error\":\"x\"}".utf8))
        }
    }

    @Test func 빈_배열은_빈_결과() throws {
        #expect(try HyperliquidCandleService.parse(Data("[]".utf8)).isEmpty)
    }
}

struct MockCandleTests {
    @Test func 목업_봉은_기간을_빈틈없이_채운다() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for range in ChartRange.allCases {
            let series = try await MockPriceService().fetchCandles(ticker: "NVDA", range: range, now: now,
                                                                      kind: nil)
            #expect(series.candles.count == Int(range.duration / range.intervalSeconds))
            #expect(series.candles.last?.end == now)
        }
    }
}

struct LivePriceParsingTests {
    /// 실제 WebSocket 메시지 발췌 (2026-11-15 확인).
    private let ctx = """
    {"channel":"activeAssetCtx","data":{"coin":"xyz:NVDA","ctx":{"prevDayPx":"162.37","oraclePx":"159.74","markPx":"159.27","midPx":"159.275"}}}
    """

    @Test func 마크_가격을_꺼낸다() {
        #expect(HyperliquidLiveStream.parse(Data(ctx.utf8)) == 159.27)
    }

    @Test func 구독_확인_메시지는_무시() {
        let ack = #"{"channel":"subscriptionResponse","data":{"method":"subscribe"}}"#
        #expect(HyperliquidLiveStream.parse(Data(ack.utf8)) == nil)
    }

    @Test func 깨진_메시지는_무시() {
        #expect(HyperliquidLiveStream.parse(Data("not json".utf8)) == nil)
        let noPrice = #"{"channel":"activeAssetCtx","data":{"ctx":{"markPx":"abc"}}}"#
        #expect(HyperliquidLiveStream.parse(Data(noPrice.utf8)) == nil)
    }
}
