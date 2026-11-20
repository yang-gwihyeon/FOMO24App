import Testing
@testable import FOMOCore

struct MarketTabTests {
    private let tickers = ["NVDA", "SMSN", "BTC", "GOLD", "NEWCO"]
    private let lookup: (String) -> MarketCategory? = { MarketCategory.builtin(for: $0) }

    @Test func 전체_탭은_그대로() {
        #expect(MarketTab.all.filter(tickers, favorites: [], category: lookup) == tickers)
    }

    @Test func 즐겨찾기_탭은_즐겨찾기만_정렬순서_유지() {
        let result = MarketTab.favorites.filter(tickers, favorites: ["GOLD", "NVDA"], category: lookup)
        #expect(result == ["NVDA", "GOLD"])
    }

    @Test func 즐겨찾기가_없으면_빈_목록() {
        #expect(MarketTab.favorites.filter(tickers, favorites: [], category: lookup) == [])
    }

    @Test func 목록에_없는_즐겨찾기는_무시() {
        #expect(MarketTab.favorites.filter(tickers, favorites: ["GONE", "BTC"], category: lookup) == ["BTC"])
    }

    @Test func 분류_탭은_해당_분류만() {
        #expect(MarketTab.category(.usStock).filter(tickers, favorites: [], category: lookup) == ["NVDA"])
        #expect(MarketTab.category(.asiaStock).filter(tickers, favorites: [], category: lookup) == ["SMSN"])
        #expect(MarketTab.category(.crypto).filter(tickers, favorites: [], category: lookup) == ["BTC"])
        #expect(MarketTab.category(.indexCommodity).filter(tickers, favorites: [], category: lookup) == ["GOLD"])
    }

    @Test func 분류_없는_종목은_전체에만() {
        for category in MarketCategory.allCases {
            let result = MarketTab.category(category).filter(tickers, favorites: [], category: lookup)
            #expect(!result.contains("NEWCO"))
        }
        #expect(MarketTab.all.filter(tickers, favorites: [], category: lookup).contains("NEWCO"))
    }

    @Test func 즐겨찾기_탭이_맨_앞() {
        #expect(MarketTab.allTabs.first == .favorites)
        #expect(MarketTab.allTabs.count == MarketCategory.allCases.count + 2)
    }

    @Test func 탭_식별자는_중복_없음() {
        #expect(Set(MarketTab.allTabs.map(\.id)).count == MarketTab.allTabs.count)
    }
}

struct CatalogCategoryTests {
    @Test func 원격_category_필드를_우선() {
        let entry = Catalog.Entry(remote: ["ticker": "NVDA", "en": "NVIDIA", "category": "crypto"])
        #expect(entry?.category == .crypto)
    }

    @Test func 원격에_category가_없으면_내장_분류표() {
        let entry = Catalog.Entry(remote: ["ticker": "BTC", "en": "Bitcoin"])
        #expect(entry?.category == .crypto)
    }

    @Test func 원격_category가_모르는_값이면_내장_분류표() {
        let entry = Catalog.Entry(remote: ["ticker": "GOLD", "en": "Gold", "category": "???"])
        #expect(entry?.category == .indexCommodity)
    }

    @Test func 모르는_종목은_분류_없음() {
        let entry = Catalog.Entry(remote: ["ticker": "NEWCO", "en": "New Co"])
        #expect(entry != nil)
        #expect(entry?.category == nil)
    }
}
