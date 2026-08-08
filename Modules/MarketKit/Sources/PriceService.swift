import Foundation
import FOMOCore

public enum PriceServiceError: LocalizedError {
    case badResponse
    case decoding

    public var errorDescription: String? {
        switch self {
        case .badResponse: return "서버 응답을 받지 못했어요."
        case .decoding:   return "가격 데이터를 해석하지 못했어요."
        }
    }
}

/// 가격 소스 추상화 — 종목 시세만 담당.
public protocol PriceService: Sendable {
    func fetchAssets() async throws -> [StockFuture]
}

/// 환율 제공자 — 소스와 무관하게 항상 동일(USD 기준). Hyperliquid FX 선물 사용.
public protocol FXProvider: Sendable {
    func fetchFXRates() async throws -> [String: Double]
}

extension DataSource {
    /// 이 소스의 실제 시세 서비스 생성. (enum 자체는 FOMOCore에 정의)
    public func makeService() -> PriceService {
        switch self {
        case .hyperliquid: return HyperliquidService()
        case .binance:     return BinanceService()
        case .bitget:      return BitgetService()
        case .bybit:       return BybitService()
        }
    }
}
