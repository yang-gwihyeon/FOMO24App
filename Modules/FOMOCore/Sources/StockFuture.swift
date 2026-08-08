import Foundation

/// 거래소(Hyperliquid)에서 24/7 거래되는 주식 선물 1종목.
/// 가격은 항상 USD 기준이며, 표시 통화 변환은 PriceStore에서 처리한다.
public struct StockFuture: Identifiable, Hashable, Sendable {
    public let ticker: String        // 예: "NVDA" (표시명은 선택 언어에 따라 Catalog에서 조회)
    public let usdPrice: Double       // 현재 마크 가격 (USD)
    public let prevDayPrice: Double    // 24시간 전 가격 (USD)
    public var volume24h: Double = 0   // 24시간 거래대금 (USD notional)

    public init(ticker: String, usdPrice: Double, prevDayPrice: Double, volume24h: Double = 0) {
        self.ticker = ticker
        self.usdPrice = usdPrice
        self.prevDayPrice = prevDayPrice
        self.volume24h = volume24h
    }

    public var id: String { ticker }

    /// 24시간 등락률 (%)
    public var change24h: Double {
        guard prevDayPrice > 0 else { return 0 }
        return (usdPrice / prevDayPrice - 1) * 100
    }

    public var isUp: Bool { change24h >= 0 }
}
