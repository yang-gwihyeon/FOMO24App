import Foundation
import FOMOCore

/// 프리뷰/오프라인 개발용 목업 (가격 + 환율 모두 제공).
public struct MockPriceService: PriceService, FXProvider {
    public init() {}

    public func fetchAssets() async throws -> [StockFuture] {
        let samples: [(String, Double, Double, Double)] = [
            ("NVDA", 209.26, 209.92, 8_500_000),
            ("SMSN", 241.27, 239.13, 1_200_000),
            ("SKHX", 1913.6, 1875.5, 900_000),
            ("SNDK", 2224.9, 2224.9, 300_000),
            ("MU",   1144.1, 1136.4, 2_100_000),
            ("TSLA", 432.10, 440.55, 6_700_000),
            ("AAPL", 258.40, 256.10, 4_400_000)
        ]
        return samples.map {
            StockFuture(ticker: $0.0, usdPrice: $0.1, prevDayPrice: $0.2, volume24h: $0.3)
        }
    }

    public func fetchFXRates() async throws -> [String: Double] {
        ["KRW": 1527.4, "JPY": 161.4, "EUR": 1.1474, "GBP": 1.33]
    }
}
