import SwiftUI

/// 위젯 전용 미니 도구 — 앱 본체와 의존성을 끊기 위해 자체 포함.
enum WK {
    // 한국식 등락 색 (앱 Theme와 동일 값)
    static let up = Color(red: 240/255, green: 68/255, blue: 82/255)     // 0xF04452
    static let down = Color(red: 49/255, green: 130/255, blue: 246/255)  // 0x3182F6
    static let accent = down

    static func changeColor(_ isUp: Bool) -> Color { isUp ? up : down }

    /// 추적 종목 (티커, 한국어명, 영어명)
    static let tickers: [(ticker: String, ko: String, en: String)] = [
        ("NVDA", "엔비디아", "NVIDIA"), ("TSLA", "테슬라", "Tesla"),
        ("AAPL", "애플", "Apple"), ("MSFT", "마이크로소프트", "Microsoft"),
        ("GOOGL", "구글", "Google"), ("AMZN", "아마존", "Amazon"),
        ("META", "메타", "Meta"), ("AMD", "AMD", "AMD"),
        ("TSM", "TSMC", "TSMC"), ("MU", "마이크론", "Micron"),
        ("SNDK", "샌디스크", "SanDisk"), ("PLTR", "팔란티어", "Palantir"),
        ("COIN", "코인베이스", "Coinbase"), ("SMSN", "삼성전자", "Samsung"),
        ("SKHX", "SK하이닉스", "SK Hynix"), ("HYUNDAI", "현대차", "Hyundai"),
        ("KIOXIA", "키오시아", "Kioxia"),
    ]

    /// 시스템 언어를 따라 한국어/영어 이름 선택 (위젯은 앱 언어 설정을 못 읽음 — 로케일 기준)
    static var isKorean: Bool {
        Locale.current.language.languageCode?.identifier == "ko"
    }

    static func name(_ ticker: String) -> String {
        guard let entry = tickers.first(where: { $0.ticker == ticker }) else { return ticker }
        return isKorean ? entry.ko : entry.en
    }

    private static let groupedFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func priceText(_ value: Double) -> String {
        // 주의: String(format:)의 "%,.0f"는 Swift 미지원 (","가 그대로 깨짐)
        value >= 1000
            ? "$" + (groupedFmt.string(from: NSNumber(value: value)) ?? String(Int(value)))
            : String(format: "$%.2f", value)
    }

    static func pctText(_ pct: Double) -> String {
        String(format: "%@%.2f%%", pct >= 0 ? "+" : "", pct)
    }
}

/// Hyperliquid에서 티커별 (가격, 24h%)를 가져온다 — 위젯 타임라인용 경량 페처.
enum WidgetFetcher {
    struct Quote {
        let ticker: String
        let price: Double
        let changePct: Double
    }

    static func fetchQuotes() async -> [String: Quote] {
        var request = URLRequest(url: URL(string: "https://api.hyperliquid.xyz/info")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "metaAndAssetCtxs", "dex": "xyz"])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              root.count >= 2,
              let meta = root[0] as? [String: Any],
              let universe = meta["universe"] as? [[String: Any]],
              let ctxs = root[1] as? [[String: Any]]
        else { return [:] }

        var quotes: [String: Quote] = [:]
        for (i, coin) in universe.enumerated() where i < ctxs.count {
            guard let rawName = coin["name"] as? String else { continue }
            let ticker = rawName.split(separator: ":").last.map(String.init) ?? rawName
            guard let markStr = ctxs[i]["markPx"] as? String, let mark = Double(markStr) else { continue }
            let prev = (ctxs[i]["prevDayPx"] as? String).flatMap(Double.init) ?? mark
            let pct = prev > 0 ? (mark / prev - 1) * 100 : 0
            quotes[ticker] = Quote(ticker: ticker, price: mark, changePct: pct)
        }
        return quotes
    }
}
