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

    public init(ticker: String, name: String) {
        self.ticker = ticker
        self.name = name
    }
}
