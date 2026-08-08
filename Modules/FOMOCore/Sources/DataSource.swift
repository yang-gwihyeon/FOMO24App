import Foundation

/// 선택 가능한 시세 데이터 소스.
/// 실제 서비스 생성(makeService)은 MarketKit의 extension에서 제공한다.
public enum DataSource: String, CaseIterable, Identifiable, Sendable {
    case hyperliquid, binance, bitget, bybit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hyperliquid: return "Hyperliquid"
        case .binance:     return "Binance"
        case .bitget:      return "Bitget"
        case .bybit:       return "Bybit"
        }
    }

    /// 마켓 헤더에 표시할 소스 라벨.
    public func label(_ lang: AppLanguage) -> String {
        let kind: String
        switch (self, lang) {
        case (.hyperliquid, .ko): kind = "무기한선물"
        case (.hyperliquid, .ja): kind = "無期限先物"
        case (.hyperliquid, _):   kind = "Perps"
        case (.binance, .ko), (.bitget, .ko): kind = "주식선물"
        case (.binance, .ja), (.bitget, .ja): kind = "株先物"
        case (.binance, _), (.bitget, _):     kind = "Stock Futures"
        case (.bybit, .ko): kind = "토큰화주식"
        case (.bybit, .ja): kind = "トークン株"
        case (.bybit, _):   kind = "xStocks"
        }
        return "\(displayName) · \(kind)"
    }
}
