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
    /// FOMO 탭 상단 쇼케이스 카드 (원격 구성 `config/fomoShowcase`, 슬라이드 3장 + 더보기 시트 최대 15개)
    private(set) var showcaseItems: [ShowcaseItem] = []

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

    /// 마켓 목록 맨 위에 고정한 종목 (1개). 정렬을 바꿔도 항상 첫 줄. UserDefaults에 저장.
    var pinnedTicker: String? = UserDefaults.standard.string(forKey: "pinnedTicker") {
        didSet { UserDefaults.standard.set(pinnedTicker, forKey: "pinnedTicker") }
    }

    /// 고정 토글 — 이미 고정된 종목이면 해제, 아니면 이 종목으로 교체.
    func togglePin(_ ticker: String, showToast: Bool = true) {
        let pinning = pinnedTicker != ticker
        pinnedTicker = pinning ? ticker : nil
        guard showToast else { return }
        toast = pinning ? appLanguage.t("맨 위에 고정했어요", "Pinned to top")
                        : appLanguage.t("고정을 해제했어요", "Unpinned")
    }

    /// 즐겨찾기 종목 (여러 개). 마켓 "즐겨찾기" 탭에 모아 보여준다. UserDefaults에 저장.
    private(set) var favoriteTickers: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "favoriteTickers") ?? []) {
        didSet { UserDefaults.standard.set(favoriteTickers.sorted(), forKey: "favoriteTickers") }
    }

    func isFavorite(_ ticker: String) -> Bool { favoriteTickers.contains(ticker) }

    func toggleFavorite(_ ticker: String) {
        let adding = !favoriteTickers.contains(ticker)
        if adding { favoriteTickers.insert(ticker) } else { favoriteTickers.remove(ticker) }
        toast = adding ? appLanguage.t("즐겨찾기에 추가했어요", "Added to favorites")
                       : appLanguage.t("즐겨찾기에서 뺐어요", "Removed from favorites")
    }

    /// 마켓 상단 탭 (즐겨찾기 · 전체 · 분류). 저장하지 않고 실행마다 init에서 정한다.
    var marketTab: MarketTab = .all

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
        // 즐겨찾기가 있으면 그 탭으로 시작. 없으면 빈 화면 대신 전체 목록부터 보여준다.
        if !favoriteTickers.isEmpty { marketTab = .favorites }
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

    /// 원격 쇼케이스 구성 적용 (RootTabView가 포그라운드 진입 시 로드).
    func applyShowcase(_ items: [ShowcaseItem]) {
        showcaseItems = items
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

    /// 정렬 → 탭 필터 → 상단 고정이 적용된 표시 종목 목록.
    var displayedTickers: [String] {
        let filtered = marketTab.filter(sortedTickers, favorites: favoriteTickers,
                                        category: Catalog.category(for:))
        return PinnedOrder.apply(filtered, pinned: pinnedTicker)
    }

    private var sortedTickers: [String] {
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

    /// 해당 통화의 현재 환율 (USD는 nil — 변환 불필요).
    func fxRate(for currency: Currency) -> Double? {
        guard currency.fxTicker != nil, let rate = fxRates[currency.code], rate > 0 else { return nil }
        return rate
    }

    /// 선택 통화 기준 가격으로 변환.
    func convertedPrice(_ usd: Double) -> Double {
        selectedCurrency.convert(usd: usd, rate: fxRate(for: selectedCurrency))
    }

    /// 통화 기호 + 자릿수 포맷팅된 문자열.
    func formatted(_ usd: Double) -> String {
        let value = convertedPrice(usd)
        let currency = selectedCurrency
        let formatter = Fmt.number(fractionDigits: currency.fractionDigits)
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(currency.symbol)\(number)"
    }

    /// 차트 축 눈금용 — 1,000 이상은 소수점을 뗀다 ("$85,000.00" → "$85,000").
    func formattedAxis(_ usd: Double) -> String {
        let value = convertedPrice(usd)
        let currency = selectedCurrency
        let digits = abs(value) >= 1000 ? 0 : currency.fractionDigits
        let number = Fmt.number(fractionDigits: digits).string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(currency.symbol)\(number)"
    }
}
