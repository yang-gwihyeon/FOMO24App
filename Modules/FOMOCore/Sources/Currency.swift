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
}
