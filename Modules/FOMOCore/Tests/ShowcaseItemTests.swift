import Foundation
import Testing
@testable import FOMOCore

struct ShowcaseItemTests {
    @Test func 원격_파싱_정상() {
        let item = ShowcaseItem(remote: [
            "ticker": "AMD", "priceUSD": 155.5,
            "ko": "9/17 FOMC 금리 발표 직전", "en": "Right before Sept FOMC",
        ])
        #expect(item?.ticker == "AMD")
        #expect(item?.priceUSD == 155.5)
        #expect(item?.event(.ko) == "9/17 FOMC 금리 발표 직전")
        #expect(item?.event(.en) == "Right before Sept FOMC")
    }

    @Test func 정수_가격도_파싱된다() {
        // Firestore REST는 155를 integerValue(Int)로 디코딩한다
        let item = ShowcaseItem(remote: ["ticker": "NVDA", "priceUSD": 155, "en": "Before earnings"])
        #expect(item?.priceUSD == 155)
    }

    @Test func 필수_필드_없으면_nil() {
        #expect(ShowcaseItem(remote: ["priceUSD": 100.0, "en": "x"]) == nil)       // ticker 없음
        #expect(ShowcaseItem(remote: ["ticker": "AMD", "en": "x"]) == nil)         // 가격 없음
        #expect(ShowcaseItem(remote: ["ticker": "AMD", "priceUSD": 0.0, "en": "x"]) == nil) // 가격 0
        #expect(ShowcaseItem(remote: ["ticker": "AMD", "priceUSD": 100.0]) == nil) // en 없음
    }

    @Test func ko_ja_없으면_en으로_대체() {
        let item = ShowcaseItem(remote: ["ticker": "AMD", "priceUSD": 100.0, "en": "Before FOMC"])
        #expect(item?.event(.ko) == "Before FOMC")
        #expect(item?.event(.ja) == "Before FOMC")
    }

    @Test func 수익률_계산은_FomoEntry와_동일() {
        let item = ShowcaseItem(ticker: "AMD", priceUSD: 100, ko: "이벤트", en: "event")
        #expect(abs(item.returnPct(currentUSD: 134.2) - 34.2) < 0.0001)
        #expect(abs(item.returnPct(currentUSD: 80) - (-20)) < 0.0001)
    }
}
