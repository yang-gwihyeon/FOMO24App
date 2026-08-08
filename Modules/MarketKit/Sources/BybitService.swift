import Foundation
import FOMOCore

/// Bybit v5 현물 시세 — xStocks(토큰화 주식, USDT 페어). API 키 불필요.
public struct BybitService: PriceService {
    private let url = URL(string: "https://api.bybit.com/v5/market/tickers?category=spot")!

    public init() {}

    public func fetchAssets() async throws -> [StockFuture] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PriceServiceError.badResponse
        }
        let payload: Response
        do { payload = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw PriceServiceError.decoding }

        let bySymbol = Dictionary(payload.result.list.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })

        return Catalog.tracked.compactMap { entry in
            guard let sym = entry.bybit, let t = bySymbol[sym],
                  let last = Double(t.lastPrice), let prev = Double(t.prevPrice24h ?? "") else { return nil }
            return StockFuture(ticker: entry.ticker, usdPrice: last,
                               prevDayPrice: prev, volume24h: Double(t.turnover24h ?? "") ?? 0)
        }
    }

    private struct Response: Decodable { let result: Result }
    private struct Result: Decodable { let list: [Ticker] }
    private struct Ticker: Decodable {
        let symbol: String
        let lastPrice: String
        let prevPrice24h: String?
        let turnover24h: String?
    }
}
