import Foundation
import FOMOCore

/// 과거 가격(봉) 소스 추상화. 현재가 비교는 PriceService가, 차트는 이 프로토콜이 담당.
public protocol CandleService: Sendable {
    /// kind: 이전 응답으로 이미 아는 종목 종류. 모르면 nil (주식부터 찾아본다).
    func fetchCandles(ticker: String, range: ChartRange, now: Date, kind: CandleKind?) async throws -> CandleSeries
}

/// 봉을 어느 쪽에서 받는 종목인지.
public enum CandleKind: Sendable {
    case stock   // 주식 선물 (xyz dex, 정규장 있음)
    case coin    // 코인 (메인 dex, 24시간)
}

/// Hyperliquid info 엔드포인트(`candleSnapshot`). API 키 불필요.
/// 주식 선물은 `xyz:NVDA`, 코인은 `BTC` 형식 — 주식 dex를 먼저 보고 없으면 코인으로 본다
/// (HyperliquidService의 "티커 충돌 시 주식 우선"과 같은 순서).
public struct HyperliquidCandleService: CandleService {
    private let endpoint = URL(string: "https://api.hyperliquid.xyz/info")!
    private let dex = "xyz"

    public init() {}

    public func fetchCandles(ticker: String, range: ChartRange, now: Date,
                             kind: CandleKind?) async throws -> CandleSeries {
        // 종류를 이미 알면 한 번만 요청한다 — 코인을 매번 주식 dex부터 찔러 보면 요청이 2배가 되고,
        // 실패한 요청도 IP당 분당 한도(가중치 1200)를 깎는다.
        if kind == .stock {
            let stock = try await request(coin: "\(dex):\(ticker)", range: range, now: now)
            guard !stock.isEmpty else { throw PriceServiceError.badResponse }
            return CandleSeries(candles: stock, isAlwaysOpen: false)
        }
        // 주식 dex에 없는 티커는 HTTP 500 또는 빈 배열이 온다 — 둘 다 "코인으로 재시도" 신호로 취급.
        if kind == nil,
           let stock = try? await request(coin: "\(dex):\(ticker)", range: range, now: now), !stock.isEmpty {
            return CandleSeries(candles: stock, isAlwaysOpen: false)
        }
        let coin = try await request(coin: ticker, range: range, now: now)
        guard !coin.isEmpty else { throw PriceServiceError.badResponse }
        return CandleSeries(candles: coin, isAlwaysOpen: true)
    }

    private func request(coin: String, range: ChartRange, now: Date) async throws -> [Candle] {
        let end = Int(now.timeIntervalSince1970 * 1000)
        let start = end - Int(range.duration * 1000)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CandleRequest(type: "candleSnapshot",
                          req: .init(coin: coin, interval: range.interval, startTime: start, endTime: end)))
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PriceServiceError.badResponse
        }
        return try Self.parse(data)
    }

    /// 응답 배열 → 봉 (시간순). 숫자가 깨진 봉은 건너뛴다 — 한 개 때문에 차트 전체를 버리지 않게.
    static func parse(_ data: Data) throws -> [Candle] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PriceServiceError.decoding
        }
        let candles: [Candle] = rows.compactMap { row in
            guard let t = (row["t"] as? NSNumber)?.doubleValue,
                  let endT = (row["T"] as? NSNumber)?.doubleValue,
                  let open = Double(row["o"] as? String ?? ""),
                  let high = Double(row["h"] as? String ?? ""),
                  let low = Double(row["l"] as? String ?? ""),
                  let close = Double(row["c"] as? String ?? ""),
                  low > 0, high >= low else { return nil }
            return Candle(start: Date(timeIntervalSince1970: t / 1000),
                          end: Date(timeIntervalSince1970: endT / 1000),
                          open: open, high: high, low: low, close: close)
        }
        return candles.sorted { $0.start < $1.start }
    }
}

private struct CandleRequest: Encodable {
    struct Req: Encodable {
        let coin: String
        let interval: String
        let startTime: Int
        let endTime: Int
    }
    let type: String
    let req: Req
}

extension MockPriceService: CandleService {
    /// 네트워크 없이 프리뷰·테스트가 돌도록 완만한 파형의 고정 봉을 만든다 (난수 없음 → 결과 재현 가능).
    public func fetchCandles(ticker: String, range: ChartRange, now: Date,
                             kind: CandleKind?) async throws -> CandleSeries {
        let base = 200.0
        let step = range.intervalSeconds
        let count = Int(range.duration / step)
        let first = now.addingTimeInterval(-range.duration)
        let candles: [Candle] = (0..<count).map { i in
            let wave = { (n: Int) in base * (1 + 0.04 * sin(Double(n) / 14) + 0.0004 * Double(n)) }
            let open = wave(i)
            let close = wave(i + 1)
            let start = first.addingTimeInterval(Double(i) * step)
            return Candle(start: start, end: start.addingTimeInterval(step),
                          open: open, high: max(open, close) * 1.002, low: min(open, close) * 0.998, close: close)
        }
        return CandleSeries(candles: candles, isAlwaysOpen: false)
    }
}
