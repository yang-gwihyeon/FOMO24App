import FOMOCore
import Foundation
import MarketKit

/// 차트 시트를 여는 대상. FOMO 탭에서 열면 해당 기록이 선택된 상태로 시작한다.
struct ChartTarget: Identifiable, Hashable {
    let ticker: String
    var focusUUID: String?

    var id: String { ticker + "|" + (focusUUID ?? "") }
}

/// 차트 위의 한 점 (USD).
struct ChartPoint: Identifiable, Hashable {
    let date: Date
    let usd: Double

    var id: Date { date }
}

/// 봉 캐시 — 같은 종목·기간은 시트를 다시 열어도 재요청하지 않는다.
/// 봉은 간격(5분~12시간)마다 한 번만 바뀌고 마지막 점은 PriceStore의 실시간 가격으로 덮으므로,
/// 간격만큼은 캐시가 낡지 않는다.
@MainActor
final class ChartStore {
    static let shared = ChartStore()

    private let service: CandleService
    private var cache: [String: (series: CandleSeries, at: Date)] = [:]
    /// 종목이 코인인지 주식인지 — 한 번 알아내면 이후 요청에서 탐색(이중 요청)을 건너뛴다.
    private var kinds: [String: CandleKind] = [:]

    init(service: CandleService = HyperliquidCandleService()) {
        self.service = service
    }

    func cached(_ ticker: String, _ range: ChartRange, now: Date = .now) -> CandleSeries? {
        // 실시간은 캐시된 봉과 지금 사이에 빈 구간이 생기므로 항상 새로 받는다
        guard range != .live, let hit = cache[key(ticker, range)],
              now.timeIntervalSince(hit.at) < range.intervalSeconds else { return nil }
        return hit.series
    }

    func load(_ ticker: String, _ range: ChartRange, now: Date = .now) async -> CandleSeries? {
        if let hit = cached(ticker, range, now: now) { return hit }
        guard let series = try? await service.fetchCandles(ticker: ticker, range: range, now: now,
                                                           kind: kinds[ticker]),
              !series.candles.isEmpty else { return nil }
        kinds[ticker] = series.isAlwaysOpen ? .coin : .stock
        cache[key(ticker, range)] = (series, now)
        return series
    }

    private func key(_ ticker: String, _ range: ChartRange) -> String { "\(ticker)|\(range.rawValue)" }
}
