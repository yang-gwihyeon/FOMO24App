// 테스트는 컴파일타임 보장 픽스처에 한해 강제 언래핑 허용 (CODE_REVIEW.md §4)
// swiftlint:disable force_unwrapping
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

    @Test func 원화_환산은_곱셈() {
        #expect(Currency.krw.convert(usd: 100, rate: 1400) == 140_000)
        #expect(Currency.jpy.convert(usd: 2, rate: 150) == 300)
    }

    @Test func 유로_환산은_나눗셈() {
        #expect(abs(Currency.eur.convert(usd: 110, rate: 1.1) - 100) < 0.0001)
    }

    @Test func 달러는_환율_무시() {
        #expect(Currency.usd.convert(usd: 123.45, rate: 1400) == 123.45)
    }

    @Test func 환율_없거나_0이면_달러값_그대로() {
        #expect(Currency.krw.convert(usd: 100, rate: nil) == 100)
        #expect(Currency.krw.convert(usd: 100, rate: 0) == 100)
        #expect(Currency.krw.convert(usd: 100, rate: -1) == 100)
    }
}

struct PriceActivityAttributesTests {
    @Test func 시작_통화와_환율로_현지가격_환산() {
        let a = PriceActivityAttributes(ticker: "NVDA", name: "엔비디아", currency: .krw, fxRate: 1400)
        #expect(a.currency == .krw)
        #expect(a.localPrice(usd: 100) == 140_000)
    }

    @Test func 비달러인데_환율없으면_달러로_시작() {
        let a = PriceActivityAttributes(ticker: "NVDA", name: "NVIDIA", currency: .krw, fxRate: nil)
        #expect(a.currency == .usd)
        #expect(a.localPrice(usd: 100) == 100)
    }

    @Test func 통화필드_없는_구버전_JSON은_달러로_복원() throws {
        let json = Data(#"{"ticker":"NVDA","name":"NVIDIA"}"#.utf8)
        let a = try JSONDecoder().decode(PriceActivityAttributes.self, from: json)
        #expect(a.currency == .usd)
        #expect(a.fxRate == 1)
        #expect(a.ticker == "NVDA")
    }

    @Test func 인코딩_디코딩_왕복() throws {
        let a = PriceActivityAttributes(ticker: "TSLA", name: "테슬라", currency: .jpy, fxRate: 150)
        let data = try JSONEncoder().encode(a)
        let b = try JSONDecoder().decode(PriceActivityAttributes.self, from: data)
        #expect(b.currency == .jpy)
        #expect(b.fxRate == 150)
        #expect(b.localPrice(usd: 2) == 300)
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

struct CurrencyCompactTextTests {
    @Test func 원화는_만_단위로_축약() {
        #expect(Currency.krw.compactText(local: 248_900) == "₩24.9만")
        #expect(Currency.krw.compactText(local: 10_000) == "₩1만")          // ".0" 제거
        #expect(Currency.krw.compactText(local: 150_000_000) == "₩1.5억")
    }

    @Test func 원화_1만_미만은_정수_그대로() {
        #expect(Currency.krw.compactText(local: 9_850) == "₩9,850")
        #expect(Currency.krw.compactText(local: 120) == "₩120")
    }

    @Test func 엔화는_일본어_단위() {
        #expect(Currency.jpy.compactText(local: 38_500) == "¥3.9万")
        #expect(Currency.jpy.compactText(local: 2_000_000) == "¥200万")
    }

    @Test func 달러는_K와_M_단위() {
        #expect(Currency.usd.compactText(local: 112_345) == "$112.3K")     // 비트코인 급
        #expect(Currency.usd.compactText(local: 1_500_000) == "$1.5M")
    }

    @Test func 달러_1만_미만은_자릿수_단계별() {
        #expect(Currency.usd.compactText(local: 1_234.56) == "$1,235")     // 1,000 이상 정수
        #expect(Currency.usd.compactText(local: 175.23) == "$175.2")       // 100 이상 소수 1자리
        #expect(Currency.usd.compactText(local: 45.678) == "$45.68")       // 그 외 소수 2자리
        #expect(Currency.eur.compactText(local: 99.5) == "€99.50")
    }

    @Test func 음수는_기호_앞에_마이너스() {
        #expect(Currency.usd.compactText(local: -12.5) == "-$12.50")
    }
}

// swiftlint:enable force_unwrapping
