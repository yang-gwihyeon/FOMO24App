import Foundation

/// 표시 통화. 환율은 Hyperliquid의 FX 선물에서 가져온다.
/// - perUSD: 1 USD = rate 단위 (KRW, JPY)  → localPrice = usd * rate
/// - perUnit: 1 단위 = rate USD (EUR, GBP)  → localPrice = usd / rate
public enum Currency: String, CaseIterable, Identifiable, Sendable {
    case usd, krw, jpy, eur, gbp

    public var id: String { rawValue }

    public enum FXMode: Sendable { case perUSD, perUnit }

    /// 표시 통화에 맞춘 회사명/라벨 언어.
    public var language: AppLanguage {
        switch self {
        case .krw: return .ko
        case .jpy: return .ja
        case .usd, .eur, .gbp: return .en
        }
    }

    public var code: String { rawValue.uppercased() }

    public var symbol: String {
        switch self {
        case .usd: return "$"
        case .krw: return "₩"
        case .jpy: return "¥"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }

    public var flag: String {
        switch self {
        case .usd: return "🇺🇸"
        case .krw: return "🇰🇷"
        case .jpy: return "🇯🇵"
        case .eur: return "🇪🇺"
        case .gbp: return "🇬🇧"
        }
    }

    /// Hyperliquid dex(xyz)에서의 FX 선물 티커. USD는 변환 불필요(nil).
    public var fxTicker: String? {
        switch self {
        case .usd: return nil
        case .krw: return "KRW"
        case .jpy: return "JPY"
        case .eur: return "EUR"
        case .gbp: return "GBP"
        }
    }

    public var mode: FXMode {
        switch self {
        case .krw, .jpy: return .perUSD
        case .eur, .gbp: return .perUnit
        case .usd: return .perUSD
        }
    }

    /// 소수점 자릿수 (원/엔은 정수로 표시)
    public var fractionDigits: Int {
        switch self {
        case .krw, .jpy: return 0
        case .usd, .eur, .gbp: return 2
        }
    }

    /// USD 가격을 이 통화로 환산. 환율이 없거나 0 이하면 USD 그대로 반환한다
    /// (환율 로드 실패 시 빈 화면 대신 달러 표시 — 앱·위젯·라이브 액티비티 공용 규칙).
    public func convert(usd: Double, rate: Double?) -> Double {
        guard fxTicker != nil, let rate, rate > 0 else { return usd }
        switch mode {
        case .perUSD: return usd * rate   // KRW, JPY
        case .perUnit: return usd / rate  // EUR, GBP
        }
    }

    /// 다이나믹 아일랜드 컴팩트 뷰용 축약 가격 (기호 포함).
    /// 컴팩트 영역은 양쪽 합쳐 10자 안팎이라 큰 수는 통화 언어의 단위로 줄인다.
    ///   ₩248,900 → "₩24.9만", ¥38,500 → "¥3.9万", $112,345 → "$112.3K", $175.23 → "$175.2", $45.67 → "$45.67"
    /// 단위는 기기 로케일이 아니라 **통화**를 따른다 — ₩에 K, $에 만이 붙는 어색함을 피하고 테스트를 결정적으로 만들기 위해.
    public func compactText(local: Double) -> String {
        let abs = Swift.abs(local)
        let sign = local < 0 ? "-" : ""
        let (big, small): (String, String) = {
            switch language {
            case .ko: return ("억", "만")
            case .ja: return ("億", "万")
            case .en: return ("M", "K")
            }
        }()
        let (bigUnit, smallUnit): (Double, Double) = language == .en ? (1_000_000, 1_000) : (100_000_000, 10_000)
        // 축약 임계값: 한/일 통화는 1만, 달러계는 1만(달러 4자리까지는 원문 유지 — "$1,234"가 "$1.2K"보다 정확)
        let threshold: Double = 10_000
        func oneDecimal(_ v: Double) -> String {
            let s = String(format: "%.1f", v)
            return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        let body: String
        if abs >= bigUnit, abs >= threshold {
            body = oneDecimal(abs / bigUnit) + big
        } else if abs >= threshold {
            body = oneDecimal(abs / smallUnit) + small
        } else if abs >= 1000 || fractionDigits == 0 {
            body = Self.groupedFormatter.string(from: NSNumber(value: abs)) ?? String(Int(abs))
        } else if abs >= 100 {
            body = String(format: "%.1f", abs)
        } else {
            body = String(format: "%.2f", abs)
        }
        return sign + symbol + body
    }

    // 뷰 바디에서 포매터를 만들지 않도록 고정 캐시 (CODE_REVIEW.md §7)
    private static let groupedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")         // 천 단위 구분자 ","로 고정 (POSIX 로케일은 구분자가 비어 있음)
        f.usesGroupingSeparator = true
        return f
    }()
}
