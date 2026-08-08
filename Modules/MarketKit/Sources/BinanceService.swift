import Foundation
import FOMOCore

/// Binance USDT-M 선물 주식 퍼프 시세. 시세 조회는 API 키 불필요.
/// (거래는 TradFi-Perps 약정이 필요하지만 공개 티커는 자유롭게 조회 가능)
public struct BinanceService: PriceService {
    private let url = URL(string: "https://fapi.binance.com/fapi/v1/ticker/24hr")!

    public init() {}

    public func fetchAssets() async throws -> [StockFuture] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PriceServiceError.badResponse
        }
        let tickers: [Ticker]
        do { tickers = try JSONDecoder().decode([Ticker].self, from: data) }
        catch { throw PriceServiceError.decoding }

        let bySymbol = Dictionary(tickers.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })

        return Catalog.tracked.compactMap { entry in
            guard let sym = entry.symbol(for: .binance), let t = bySymbol[sym],
                  let last = Double(t.lastPrice) else { return nil }
            let prev = Double(t.openPrice ?? "").flatMap { $0 > 0 ? $0 : nil } ?? last
            return StockFuture(ticker: entry.ticker, usdPrice: last,
                               prevDayPrice: prev, volume24h: Double(t.quoteVolume ?? "") ?? 0)
        }
    }

    private struct Ticker: Decodable {
        let symbol: String
        let lastPrice: String
        let openPrice: String?
        let quoteVolume: String?
    }
}
