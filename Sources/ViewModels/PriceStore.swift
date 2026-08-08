import FOMOCore
import MarketKit
import SwiftUI
import Observation

@MainActor
@Observable
final class PriceStore {
    // 데이터: 종목(ticker) → 거래소별 시세
    private(set) var quotes: [String: [DataSource: StockFuture]] = [:]
    private(set) var tickers: [String] = []          // 사용 가능한 종목 (Catalog 순서)
    private(set) var fxRates: [String: Double] = [:]
    private(set) var lastUpdated: Date?

    // 상태
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }
    private(set) var phase: Phase = .idle

    // 사용자 설정
    var selectedCurrency: Currency = .usd
    var sortOption: SortOption = .recommended
    /// 앱 전체 표시 언어 (한국어/영어). 더보기 탭에서 변경, UserDefaults에 저장.
    var appLanguage: AppLanguage = .current {
        didSet { UserDefaults.standard.set(appLanguage == .ko ? "ko" : "en", forKey: "appLanguage") }
    }

    /// 마켓 리스트 정렬 기준.
    enum SortOption: String, CaseIterable, Identifiable {
        case recommended, changeDesc, name, volumeDesc
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .recommended: return "star"
            case .changeDesc:  return "percent"
            case .name:        return "textformat"
            case .volumeDesc:  return "chart.bar"
            }
        }

        /// 선택 시 표시할 방향 화살표 (높은순 등). 없으면 nil.
        var arrow: String? {
            switch self {
            case .changeDesc, .volumeDesc: return "arrow.down"
            case .recommended, .name:      return nil
            }
        }

        func label(_ lang: AppLanguage) -> String {
            switch (self, lang) {
            case (.recommended, .ko): return "추천순"
            case (.recommended, .ja): return "おすすめ順"
            case (.recommended, _):   return "Recommended"
            case (.changeDesc, .ko):  return "수익률순"
            case (.changeDesc, .ja):  return "騰落率順"
            case (.changeDesc, _):    return "% Change"
            case (.name, .ko):        return "가나다순"
            case (.name, .ja):        return "名前順"
            case (.name, _):          return "Name"
            case (.volumeDesc, .ko):  return "거래량순"
            case (.volumeDesc, .ja):  return "出来高順"
            case (.volumeDesc, _):    return "Volume"
            }
        }
    }

    /// 토스트 메시지 (FOMO 추가 확인 등). 표시 후 nil로 초기화.
    var toast: String?

    /// 폴링 주기(초) — 앱이 켜져 있을 때 자동 갱신.
    let refreshInterval: UInt64 = 5

    /// 프리뷰/테스트용 주입 서비스 (가격+환율 둘 다). nil이면 실서비스.
    private let injected: (PriceService & FXProvider)?
    private var pollingTask: Task<Void, Never>?

    private var fxService: FXProvider { injected ?? HyperliquidService() }

    init(injected: (PriceService & FXProvider)? = nil) {
        self.injected = injected
    }

    // MARK: - 갱신

    /// 단발성 갱신 — 모든 거래소 + 환율을 동시에 요청.
    func refresh() async {
        if quotes.isEmpty { phase = .loading }
        async let allTask = fetchAllSources()
        async let fxTask = try? await fxService.fetchFXRates()
        let (all, fx) = await (allTask, fxTask)

        guard !all.isEmpty else {
            phase = quotes.isEmpty ? .failed("네트워크 오류가 발생했어요.") : .loaded
            return
        }
        var q: [String: [DataSource: StockFuture]] = [:]
        for (src, assets) in all {
            for a in assets { q[a.ticker, default: [:]][src] = a }
        }
        self.quotes = q
        self.tickers = Catalog.tracked.map(\.ticker).filter { q[$0] != nil }
        if let fx, !fx.isEmpty { self.fxRates = fx }
        self.lastUpdated = Date()
        self.phase = .loaded
    }

    /// 모든 소스에서 동시에 시세를 받아온다. 일부 실패는 무시(부분 표시).
    private func fetchAllSources() async -> [DataSource: [StockFuture]] {
        if let injected {
            let assets = (try? await injected.fetchAssets()) ?? []
            return [.hyperliquid: assets]
        }
        return await withTaskGroup(of: (DataSource, [StockFuture]).self) { group in
            for source in DataSource.allCases {
                group.addTask {
                    let assets = (try? await source.makeService().fetchAssets()) ?? []
                    return (source, assets)
                }
            }
            var result: [DataSource: [StockFuture]] = [:]
            for await (source, assets) in group where !assets.isEmpty {
                result[source] = assets
            }
            return result
        }
    }

    // MARK: - 종목별 조회

    /// 대표 시세 (Hyperliquid 우선, 없으면 가용한 첫 거래소).
    func primary(_ ticker: String) -> StockFuture? {
        let m = quotes[ticker] ?? [:]
        for source in DataSource.allCases { if let f = m[source] { return f } }
        return nil
    }

    /// 종목의 거래소별 시세 (없는 곳은 빠짐).
    func sources(for ticker: String) -> [DataSource: StockFuture] { quotes[ticker] ?? [:] }

    // MARK: - 폴링 (포그라운드 전용)

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.refreshInterval * 1_000_000_000)
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    /// 백그라운드 진입 시 호출 — 갱신 중단으로 배터리/네트워크 절약.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - 정렬 (대표 시세 기준)

    /// 정렬이 적용된 표시 종목 목록.
    var displayedTickers: [String] {
        switch sortOption {
        case .recommended:
            return tickers // Catalog 순서
        case .changeDesc:
            return tickers.sorted { (primary($0)?.change24h ?? 0) > (primary($1)?.change24h ?? 0) }
        case .volumeDesc:
            return tickers.sorted { (primary($0)?.volume24h ?? 0) > (primary($1)?.volume24h ?? 0) }
        case .name:
            let lang = appLanguage
            return tickers.sorted {
                Catalog.name(for: $0, language: lang)
                    .localizedCompare(Catalog.name(for: $1, language: lang)) == .orderedAscending
            }
        }
    }

    /// 해당 종목의 대표 USD 가격 (없으면 nil).
    func currentUSDPrice(for ticker: String) -> Double? {
        primary(ticker)?.usdPrice
    }

    // MARK: - 통화 변환

    /// 선택 통화 기준 가격으로 변환.
    func convertedPrice(_ usd: Double) -> Double {
        let currency = selectedCurrency
        guard let fxTicker = currency.fxTicker else { return usd } // USD
        guard let rate = fxRates[currency.code], rate > 0 else { return usd }
        _ = fxTicker
        switch currency.mode {
        case .perUSD:  return usd * rate   // KRW, JPY
        case .perUnit: return usd / rate   // EUR, GBP
        }
    }

    /// 통화 기호 + 자릿수 포맷팅된 문자열.
    func formatted(_ usd: Double) -> String {
        let value = convertedPrice(usd)
        let currency = selectedCurrency
        let formatter = Fmt.number(fractionDigits: currency.fractionDigits)
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(currency.symbol)\(number)"
    }
}
