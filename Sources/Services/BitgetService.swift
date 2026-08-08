import Foundation

/// Bitget USDT-margined 주식 선물 시세. API 키 불필요.
struct BitgetService: PriceService {
    private let url = URL(string: "https://api.bitget.com/api/v2/mix/market/tickers?productType=usdt-futures")!

    func fetchAssets() async throws -> [StockFuture] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PriceServiceError.badResponse
        }
        let payload: Response
        do { payload = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw PriceServiceError.decoding }

        let bySymbol = Dictionary(payload.data.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })

        return Catalog.tracked.compactMap { entry in
            guard let sym = entry.bitget, let t = bySymbol[sym], let last = Double(t.lastPr) else { return nil }
            // 전일 가격: open24h 우선, 없으면 변동률로 역산
            let prev: Double
            if let o = t.open24h, let ov = Double(o), ov > 0 {
                prev = ov
            } else if let c = t.change24h, let cv = Double(c) {
                prev = last / (1 + cv)
            } else {
                prev = last
            }
            let vol = Double(t.usdtVolume ?? t.quoteVolume ?? "") ?? 0
            return StockFuture(ticker: entry.ticker, usdPrice: last, prevDayPrice: prev, volume24h: vol)
        }
    }

    private struct Response: Decodable { let data: [Ticker] }
    private struct Ticker: Decodable {
        let symbol: String
        let lastPr: String
        let open24h: String?
        let change24h: String?
        let quoteVolume: String?
        let usdtVolume: String?
    }
}
