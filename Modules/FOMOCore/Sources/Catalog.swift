import Foundation

/// 추적 종목: 티커 / 언어별 회사명 / 로고 도메인 / 소스별 심볼.
/// Hyperliquid `xyz` dex 티커가 기준. Bybit·Bitget은 미국 주식 위주라 없으면 nil.
public enum Catalog {
    public struct Entry: Sendable {
        public let ticker: String        // Hyperliquid 기준 (예: "NVDA")
        public let domain: String
        public let en: String
        public let ko: String
        public let ja: String
        public let bybit: String?        // Bybit spot 심볼 (예: "NVDAXUSDT")
        public let bitget: String?       // Bitget USDT-futures 심볼 (예: "NVDAUSDT")

        public func name(_ language: AppLanguage) -> String {
            switch language {
            case .en: return en
            case .ko: return ko
            case .ja: return ja
            }
        }

        public func symbol(for source: DataSource) -> String? {
            switch source {
            case .hyperliquid:    return ticker
            case .bybit:          return bybit
            case .bitget, .binance: return bitget   // 둘 다 base+"USDT" 동일 포맷
            }
        }
    }

    public static let tracked: [Entry] = [
        Entry(ticker: "NVDA",   domain: "nvidia.com",    en: "NVIDIA",        ko: "엔비디아",       ja: "エヌビディア",   bybit: "NVDAXUSDT",  bitget: "NVDAUSDT"),
        Entry(ticker: "SMSN",   domain: "samsung.com",   en: "Samsung Elec.", ko: "삼성전자",       ja: "サムスン電子",   bybit: nil,          bitget: nil),
        Entry(ticker: "SKHX",   domain: "skhynix.com",   en: "SK hynix",      ko: "SK하이닉스",     ja: "SKハイニックス", bybit: nil,          bitget: nil),
        Entry(ticker: "SNDK",   domain: "sandisk.com",   en: "SanDisk",       ko: "샌디스크",       ja: "サンディスク",   bybit: "SNDKXUSDT",  bitget: "SNDKUSDT"),
        Entry(ticker: "MU",     domain: "micron.com",    en: "Micron",        ko: "마이크론",       ja: "マイクロン",     bybit: "MUXUSDT",    bitget: "MUUSDT"),
        Entry(ticker: "KIOXIA", domain: "kioxia.com",    en: "Kioxia",        ko: "키오시아",       ja: "キオクシア",     bybit: nil,          bitget: nil),
        Entry(ticker: "TSLA",   domain: "tesla.com",     en: "Tesla",         ko: "테슬라",         ja: "テスラ",         bybit: "TSLAXUSDT",  bitget: "TSLAUSDT"),
        Entry(ticker: "AAPL",   domain: "apple.com",     en: "Apple",         ko: "애플",           ja: "アップル",       bybit: "AAPLXUSDT",  bitget: "AAPLUSDT"),
        Entry(ticker: "MSFT",   domain: "microsoft.com", en: "Microsoft",     ko: "마이크로소프트", ja: "マイクロソフト", bybit: "MSFTXUSDT",  bitget: "MSFTUSDT"),
        Entry(ticker: "GOOGL",  domain: "google.com",    en: "Alphabet",      ko: "알파벳(구글)",   ja: "アルファベット", bybit: "GOOGLXUSDT", bitget: "GOOGLUSDT"),
        Entry(ticker: "AMZN",   domain: "amazon.com",    en: "Amazon",        ko: "아마존",         ja: "アマゾン",       bybit: "AMZNXUSDT",  bitget: "AMZNUSDT"),
        Entry(ticker: "META",   domain: "meta.com",      en: "Meta",          ko: "메타",           ja: "メタ",           bybit: "METAXUSDT",  bitget: "METAUSDT"),
        Entry(ticker: "AMD",    domain: "amd.com",       en: "AMD",           ko: "AMD",            ja: "AMD",            bybit: "AMDXUSDT",   bitget: "AMDUSDT"),
        Entry(ticker: "TSM",    domain: "tsmc.com",      en: "TSMC",          ko: "TSMC",           ja: "TSMC",           bybit: "TSMXUSDT",   bitget: "TSMUSDT"),
        Entry(ticker: "HYUNDAI", domain: "hyundai.com",  en: "Hyundai Motor", ko: "현대차",         ja: "現代自動車",     bybit: nil,          bitget: nil),
        Entry(ticker: "COIN",   domain: "coinbase.com",  en: "Coinbase",      ko: "코인베이스",     ja: "コインベース",   bybit: "COINXUSDT",  bitget: "COINUSDT"),
        Entry(ticker: "PLTR",   domain: "palantir.com",  en: "Palantir",      ko: "팔란티어",       ja: "パランティア",   bybit: "PLTRXUSDT",  bitget: "PLTRUSDT")
    ]

    private static let byTicker: [String: Entry] = Dictionary(uniqueKeysWithValues: tracked.map { ($0.ticker, $0) })

    public static let tickerSet = Set(tracked.map { $0.ticker })

    public static func name(for ticker: String, language: AppLanguage) -> String {
        byTicker[ticker]?.name(language) ?? ticker
    }

    public static func logoURL(for ticker: String) -> URL? {
        guard let domain = byTicker[ticker]?.domain else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128")
    }

    public static func order(of ticker: String) -> Int {
        tracked.firstIndex { $0.ticker == ticker } ?? Int.max
    }
}
