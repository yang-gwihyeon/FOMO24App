import Foundation
import ActivityKit

/// 다이나믹 아일랜드/잠금화면 라이브 액티비티 — 종목 1개의 실시간 가격.
/// 앱 타겟과 위젯 익스텐션 양쪽에서 FOMOCore로 공유.
public struct PriceActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var price: Double        // USD
        public var changePct: Double    // 24h %
        public var updatedAt: Double    // unix 초 — 서버(APNs) JSON과 호환 위해 Date 대신 Double

        public init(price: Double, changePct: Double, updatedAt: Double) {
            self.price = price
            self.changePct = changePct
            self.updatedAt = updatedAt
        }
    }

    public var ticker: String           // 예: "NVDA"
    public var name: String             // 표시명 (시작 시점 언어 기준)
    /// 표시 통화 코드 (추적 시작 시점의 선택 통화). 서버 푸시는 USD만 보내므로
    /// 위젯이 `fxRate`로 환산해 표시한다.
    public var currencyCode: String
    /// 추적 시작 시점 환율 (Currency.FXMode 방향). USD면 1.
    /// 액티비티 수명(최대 8시간) 동안 고정 — 원/엔 일중 변동은 1% 미만이라 허용.
    public var fxRate: Double

    /// 환율이 필요한 통화인데 환율이 없으면 USD로 시작한다 — "₩" 기호에 달러 숫자가 붙는 오표시 방지.
    public init(ticker: String, name: String, currency: Currency = .usd, fxRate: Double? = nil) {
        self.ticker = ticker
        self.name = name
        let usable = currency.fxTicker == nil || (fxRate ?? 0) > 0
        self.currencyCode = usable ? currency.code : Currency.usd.code
        self.fxRate = usable ? (fxRate ?? 1) : 1
    }

    public var currency: Currency {
        Currency(rawValue: currencyCode.lowercased()) ?? .usd
    }

    /// 서버/앱이 보내는 USD 가격을 시작 시점 통화로 환산.
    public func localPrice(usd: Double) -> Double {
        currency.convert(usd: usd, rate: fxRate)
    }

    // 통화 필드가 없는 구버전 액티비티(업데이트 전 시작)도 복원되도록 기본값 USD로 디코딩.
    private enum CodingKeys: String, CodingKey { case ticker, name, currencyCode, fxRate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? Currency.usd.code
        self.init(
            ticker: try c.decode(String.self, forKey: .ticker),
            name: try c.decode(String.self, forKey: .name),
            currency: Currency(rawValue: code.lowercased()) ?? .usd,
            fxRate: try c.decodeIfPresent(Double.self, forKey: .fxRate))
    }
}
