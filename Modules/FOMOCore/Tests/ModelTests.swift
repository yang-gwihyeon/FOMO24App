import Foundation
import Testing
@testable import FOMOCore

struct StockFutureTests {
    @Test func 등락률_계산() {
        let f = StockFuture(ticker: "NVDA", usdPrice: 110, prevDayPrice: 100)
        #expect(abs(f.change24h - 10) < 0.0001)
        #expect(f.isUp)
    }

    @Test func 전일가_0이면_등락률_0() {
        let f = StockFuture(ticker: "NVDA", usdPrice: 110, prevDayPrice: 0)
        #expect(f.change24h == 0)
    }

    @Test func 하락시_isUp_false() {
        let f = StockFuture(ticker: "TSLA", usdPrice: 90, prevDayPrice: 100)
        #expect(!f.isUp)
        #expect(abs(f.change24h - (-10)) < 0.0001)
    }
}

struct CurrencyTests {
    @Test func 원화는_정수_표시() {
        #expect(Currency.krw.fractionDigits == 0)
        #expect(Currency.jpy.fractionDigits == 0)
        #expect(Currency.usd.fractionDigits == 2)
    }

    @Test func 환율_방향() {
        #expect(Currency.krw.mode == .perUSD)
        #expect(Currency.eur.mode == .perUnit)
    }

    @Test func 달러는_환율티커_없음() {
        #expect(Currency.usd.fxTicker == nil)
        #expect(Currency.krw.fxTicker == "KRW")
    }

    @Test func 통화코드는_대문자() {
        for c in Currency.allCases {
            #expect(c.code == c.rawValue.uppercased())
        }
    }
}

struct CatalogTests {
    @Test func 미등록_티커는_티커를_그대로_반환() {
        #expect(Catalog.name(for: "UNKNOWN", language: .ko) == "UNKNOWN")
    }

    @Test func 언어별_이름() {
        #expect(Catalog.name(for: "NVDA", language: .ko) == "엔비디아")
        #expect(Catalog.name(for: "NVDA", language: .en) == "NVIDIA")
    }

    @Test func 미등록_티커는_로고없음_순서최하위() {
        #expect(Catalog.logoURL(for: "UNKNOWN") == nil)
        #expect(Catalog.order(of: "UNKNOWN") == Int.max)
        #expect(Catalog.order(of: "NVDA") == 0)
    }

    @Test func 소스별_심볼_매핑() {
        let nvda = Catalog.tracked.first { $0.ticker == "NVDA" }!
        #expect(nvda.symbol(for: .hyperliquid) == "NVDA")
        #expect(nvda.symbol(for: .bybit) == "NVDAXUSDT")
        #expect(nvda.symbol(for: .binance) == "NVDAUSDT")
        // 삼성전자는 국내 주식 — Bybit/Bitget 미지원
        let smsn = Catalog.tracked.first { $0.ticker == "SMSN" }!
        #expect(smsn.symbol(for: .bybit) == nil)
    }
}

struct AppLanguageTests {
    @Test func 한영_헬퍼() {
        #expect(AppLanguage.ko.t("한국어", "English") == "한국어")
        #expect(AppLanguage.en.t("한국어", "English") == "English")
        #expect(AppLanguage.ja.t("한국어", "English") == "English")   // ja는 en으로
    }

    @Test func 마켓펄스_복수형() {
        #expect(AppLanguage.en.marketPulse(openCount: 1) == "1 market open")
        #expect(AppLanguage.en.marketPulse(openCount: 2) == "2 markets open")
        #expect(AppLanguage.ko.marketPulse(openCount: 0) == "정규장 전체 마감 · 24H 거래중")
    }
}
