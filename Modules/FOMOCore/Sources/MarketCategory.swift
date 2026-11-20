import Foundation

/// 마켓 목록의 종목 분류. 원격 카탈로그(`config/catalog`)의 `category` 문자열과 rawValue가 같다.
public enum MarketCategory: String, CaseIterable, Sendable {
    case usStock, asiaStock, indexCommodity, crypto

    public func label(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.usStock, .ko):        return "미국주식"
        case (.usStock, .ja):        return "米国株"
        case (.usStock, .en):        return "US Stocks"
        case (.asiaStock, .ko):      return "아시아주식"
        case (.asiaStock, .ja):      return "アジア株"
        case (.asiaStock, .en):      return "Asia"
        case (.indexCommodity, .ko): return "지수·원자재"
        case (.indexCommodity, .ja): return "指数・商品"
        case (.indexCommodity, .en): return "Index & Commodities"
        case (.crypto, .ko):         return "코인"
        case (.crypto, .ja):         return "暗号資産"
        case (.crypto, .en):         return "Crypto"
        }
    }

    /// 원격 카탈로그에 `category`가 없는 종목의 분류.
    /// 이미 배포된 `config/catalog` 문서에는 이 필드가 없어서, 문서를 고치지 않아도 탭이 채워지게 앱에 둔다.
    /// 여기에도 없는 새 종목은 "전체" 탭에만 나온다 → 문서에 `category`를 넣어 추가할 것.
    public static func builtin(for ticker: String) -> MarketCategory? { builtinMap[ticker] }

    private static let builtinMap: [String: MarketCategory] = {
        let groups: [(MarketCategory, [String])] = [
            (.usStock, ["NVDA", "SNDK", "MU", "TSLA", "AAPL", "MSFT", "GOOGL", "AMZN", "META", "AMD", "TSM",
                        "COIN", "PLTR", "ORCL", "HOOD", "INTC", "MSTR", "CRCL", "AVGO", "ARM", "MRVL", "NFLX",
                        "CRWV", "RKLB", "LLY", "BABA", "GME", "IREN"]),
            (.asiaStock, ["SMSN", "SKHX", "KIOXIA", "HYUNDAI"]),
            (.indexCommodity, ["SP500", "XYZ100", "GOLD", "SILVER", "CL", "BRENTOIL", "COPPER", "DRAM"]),
            (.crypto, ["BTC", "ETH", "SOL", "XRP", "DOGE"])
        ]
        var map: [String: MarketCategory] = [:]
        for (category, tickers) in groups {
            for ticker in tickers { map[ticker] = category }
        }
        return map
    }()
}

/// 마켓 화면 상단 탭 — 즐겨찾기 · 전체 · 분류별.
public enum MarketTab: Hashable, Sendable {
    case favorites
    case all
    case category(MarketCategory)

    /// 표시 순서. 즐겨찾기가 맨 앞.
    public static let allTabs: [MarketTab] = [.favorites, .all] + MarketCategory.allCases.map(MarketTab.category)

    /// 통계·UI 테스트 식별자용 (언어와 무관).
    public var id: String {
        switch self {
        case .favorites:              return "favorites"
        case .all:                    return "all"
        case .category(let category): return category.rawValue
        }
    }

    public func label(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.favorites, .ko): return "즐겨찾기"
        case (.favorites, .ja): return "お気に入り"
        case (.favorites, .en): return "Favorites"
        case (.all, .ko):       return "전체"
        case (.all, .ja):       return "すべて"
        case (.all, .en):       return "All"
        case (.category(let category), _): return category.label(language)
        }
    }

    /// 이 탭에 보일 종목만 남긴다. 입력 순서(정렬 결과)는 그대로.
    public func filter(_ tickers: [String], favorites: Set<String>,
                       category: (String) -> MarketCategory?) -> [String] {
        switch self {
        case .all:               return tickers
        case .favorites:         return tickers.filter { favorites.contains($0) }
        case .category(let own): return tickers.filter { category($0) == own }
        }
    }
}
