import Foundation
import Testing
import FOMOCore
@testable import MarketKit

struct MockPriceServiceTests {
    @Test func 목업_시세는_카탈로그_티커만() async throws {
        let assets = try await MockPriceService().fetchAssets()
        #expect(!assets.isEmpty)
        for asset in assets {
            #expect(Catalog.tickerSet.contains(asset.ticker))
        }
    }

    @Test func 목업_환율은_전체_통화_포함() async throws {
        let fx = try await MockPriceService().fetchFXRates()
        for currency in Currency.allCases {
            guard let ticker = currency.fxTicker else { continue }
            #expect(fx[ticker] != nil, "\(ticker) 환율 누락")
        }
    }
}

struct DataSourceTests {
    @Test func 소스별_서비스_생성() {
        #expect(DataSource.hyperliquid.makeService() is HyperliquidService)
        #expect(DataSource.binance.makeService() is BinanceService)
        #expect(DataSource.bitget.makeService() is BitgetService)
        #expect(DataSource.bybit.makeService() is BybitService)
    }
}

struct PriceServiceErrorTests {
    @Test func 에러_메시지_존재() {
        #expect(PriceServiceError.badResponse.errorDescription?.isEmpty == false)
        #expect(PriceServiceError.decoding.errorDescription?.isEmpty == false)
    }
}
