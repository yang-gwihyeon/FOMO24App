import Foundation

enum PriceServiceError: LocalizedError {
    case badResponse
    case decoding

    var errorDescription: String? {
        switch self {
        case .badResponse: return "서버 응답을 받지 못했어요."
        case .decoding:   return "가격 데이터를 해석하지 못했어요."
        }
    }
}

/// 가격 소스 추상화 — 종목 시세만 담당.
protocol PriceService: Sendable {
    func fetchAssets() async throws -> [StockFuture]
}

/// 환율 제공자 — 소스와 무관하게 항상 동일(USD 기준). Hyperliquid FX 선물 사용.
protocol FXProvider: Sendable {
    func fetchFXRates() async throws -> [String: Double]
}

/// 선택 가능한 데이터 소스.
enum DataSource: String, CaseIterable, Identifiable {
    case hyperliquid, binance, bitget, bybit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hyperliquid: return "Hyperliquid"
        case .binance:     return "Binance"
        case .bitget:      return "Bitget"
        case .bybit:       return "Bybit"
        }
    }

    /// 마켓 헤더에 표시할 소스 라벨.
    func label(_ lang: AppLanguage) -> String {
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

    func makeService() -> PriceService {
        switch self {
        case .hyperliquid: return HyperliquidService()
        case .binance:     return BinanceService()
        case .bitget:      return BitgetService()
        case .bybit:       return BybitService()
        }
    }
}
