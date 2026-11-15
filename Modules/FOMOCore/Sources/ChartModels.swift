import Foundation

/// 차트용 봉 1개 (USD 기준). 선 차트와 기간 범위 계산은 종가만 쓴다.
public struct Candle: Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double

    public init(start: Date, end: Date, open: Double, high: Double, low: Double, close: Double) {
        self.start = start
        self.end = end
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

/// 한 종목·한 기간의 봉 묶음.
public struct CandleSeries: Hashable, Sendable {
    public let candles: [Candle]
    /// 코인처럼 24시간 거래되는 종목 — 정규장 띠를 그리지 않는다.
    public let isAlwaysOpen: Bool

    public init(candles: [Candle], isAlwaysOpen: Bool) {
        self.candles = candles
        self.isAlwaysOpen = isAlwaysOpen
    }
}

/// 차트 기간. 기간마다 점 개수가 170~290개가 되도록 봉 간격을 고정한다
/// (너무 촘촘하면 훑기가 느려지고, 너무 성기면 FOMO 기록 시점이 뭉개진다).
///
/// `.live`만 예외: 거래소가 과거를 1초 단위로 주지 않아(최소 1분봉) 최근 5분을 1분봉으로 깔고,
/// 그 뒤는 실시간 가격을 1초마다 이어 붙인다.
public enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case live, day, week, month, quarter

    public var id: String { rawValue }

    public var duration: TimeInterval {
        switch self {
        case .live:    return 300
        case .day:     return 86_400
        case .week:    return 7 * 86_400
        case .month:   return 30 * 86_400
        case .quarter: return 90 * 86_400
        }
    }

    /// Hyperliquid candleSnapshot의 interval 값.
    public var interval: String {
        switch self {
        case .live:    return "1m"
        case .day:     return "5m"
        case .week:    return "1h"
        case .month:   return "4h"
        case .quarter: return "12h"
        }
    }

    public var intervalSeconds: TimeInterval {
        switch self {
        case .live:    return 60
        case .day:     return 300
        case .week:    return 3_600
        case .month:   return 4 * 3_600
        case .quarter: return 12 * 3_600
        }
    }

    /// 정규장 띠는 하루 단위가 눈에 보이는 기간에서만 의미가 있다.
    public var showsSessionBands: Bool { self == .day || self == .week }

    /// 헤드라인 문장용 — "최근 5분 중 고점 근처" 처럼 기간 길이로 읽히는 이름.
    public func spanLabel(_ lang: AppLanguage) -> String {
        self == .live ? lang.t("5분", "5m") : label(lang)
    }

    public func label(_ lang: AppLanguage) -> String {
        switch self {
        case .live:    return lang.t("실시간", "Live")
        case .day:     return lang.t("1일", "1D")
        case .week:    return lang.t("1주", "1W")
        case .month:   return lang.t("1달", "1M")
        case .quarter: return lang.t("3달", "3M")
        }
    }
}

/// "지금 싼 편인가 비싼 편인가" — 기간 최저~최고 범위에서 현재가의 위치.
public struct PriceRangeStats: Equatable, Sendable {
    public enum Zone: Sendable { case low, mid, high }

    public let low: Double
    public let high: Double
    /// 0(최저) ~ 1(최고)
    public let position: Double
    /// 기간 시작가 대비 현재가 등락률(%)
    public let changePct: Double

    /// 범위는 종가 기준 — 화면의 선과 같은 값이어야 "최저·최고"가 눈에 보이는 것과 일치한다
    /// (봉의 저가·고가를 쓰면 얇은 선물 시장의 순간 꼬리 때문에 선에 없는 가격이 최저로 나온다).
    /// 현재가가 범위를 벗어나면(방금 신고가 등) 범위를 현재가까지 넓힌다.
    public init?(candles: [Candle], current: Double) {
        guard let first = candles.first else { return nil }
        self.init(closes: candles.map(\.close), open: first.open, current: current)
    }

    /// 화면에 그린 점 그대로 계산 (실시간 탭은 봉이 아니라 1초 점이라 이쪽을 쓴다).
    public init?(closes: [Double], open: Double, current: Double) {
        guard !closes.isEmpty, current > 0 else { return nil }
        let low = min(closes.min() ?? current, current)
        let high = max(closes.max() ?? current, current)
        guard low > 0 else { return nil }
        self.low = low
        self.high = high
        self.position = high > low ? (current - low) / (high - low) : 0.5
        self.changePct = open > 0 ? (current / open - 1) * 100 : 0
    }

    public var zone: Zone {
        if position >= 0.8 { return .high }
        if position <= 0.2 { return .low }
        return .mid
    }
}

extension MarketSession {
    /// 종목이 상장된 본시장 ID. 카탈로그에 시장 정보가 없어 미국 외 종목만 예외로 둔다.
    public static func marketID(forTicker ticker: String) -> String {
        switch ticker {
        case "SMSN", "SKHX", "HYUNDAI": return "kr"
        case "KIOXIA": return "jp"
        default: return "us"
        }
    }
}
