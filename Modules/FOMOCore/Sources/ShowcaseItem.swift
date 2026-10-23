import Foundation

/// FOMO 탭 상단 쇼케이스 카드 한 장 — "이벤트 직전/직후에 샀다면" 훅.
/// Firestore `config/fomoShowcase`에서 내려받고, 수익률은 앱이 현재가와 비교해 계산한다
/// → 이벤트·기준가 교체는 앱 업데이트 없이 문서 수정만으로 전 사용자 반영.
public struct ShowcaseItem: Sendable, Identifiable {
    public let ticker: String       // Catalog 기준 티커 (예: "AMD")
    public let priceUSD: Double     // 이벤트 시점 가격 (USD)
    public let ko: String           // 이벤트 설명 (예: "9/17 FOMC 금리 발표 직전")
    public let en: String
    public let ja: String

    public var id: String { "\(ticker)|\(priceUSD)|\(en)" }

    public init(ticker: String, priceUSD: Double, ko: String, en: String, ja: String? = nil) {
        self.ticker = ticker
        self.priceUSD = priceUSD
        self.ko = ko
        self.en = en
        self.ja = ja ?? en
    }

    /// Firestore `config/fomoShowcase`의 entries 항목 파싱. 필수 필드(티커·양수 가격·en) 없으면 nil.
    public init?(remote: [String: Any]) {
        // REST 디코더는 정수 입력(예: 155)을 Int로 돌려주므로 둘 다 허용
        let price = (remote["priceUSD"] as? Double) ?? (remote["priceUSD"] as? Int).map(Double.init)
        guard let ticker = remote["ticker"] as? String, !ticker.isEmpty,
              let priceUSD = price, priceUSD > 0,
              let en = remote["en"] as? String, !en.isEmpty else { return nil }
        self.init(ticker: ticker,
                  priceUSD: priceUSD,
                  ko: (remote["ko"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? en,
                  en: en,
                  ja: remote["ja"] as? String)
    }

    public func event(_ language: AppLanguage) -> String {
        switch language {
        case .en: return en
        case .ko: return ko
        case .ja: return ja
        }
    }

    /// 이벤트 시점 가격 대비 현재가 수익률(%) — FomoEntry.returnPct와 동일 공식.
    public func returnPct(currentUSD: Double) -> Double {
        guard priceUSD > 0 else { return 0 }
        return (currentUSD / priceUSD - 1) * 100
    }
}
