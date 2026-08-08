import Foundation

/// 포매터 캐시 — DateFormatter/NumberFormatter 생성은 수 ms짜리 비싼 작업이라
/// 뷰 바디에서 매번 만들면 리스트 전체 리렌더 시 메인 스레드가 수백 ms 멈춘다.
/// UI(메인 스레드) 전용 — 캐시가 가변 상태라 @MainActor로 격리.
@MainActor
public enum Fmt {
    private static var dateCache: [String: DateFormatter] = [:]

    public static func date(_ format: String, locale: Locale? = nil) -> DateFormatter {
        let key = format + "|" + (locale?.identifier ?? "-")
        if let cached = dateCache[key] { return cached }
        let f = DateFormatter()
        if let locale { f.locale = locale }
        f.dateFormat = format
        dateCache[key] = f
        return f
    }

    private static var numberCache: [Int: NumberFormatter] = [:]

    /// 소수 자릿수별 decimal 포매터.
    public static func number(fractionDigits: Int) -> NumberFormatter {
        if let cached = numberCache[fractionDigits] { return cached }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        numberCache[fractionDigits] = f
        return f
    }
}
