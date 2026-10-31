import FirebaseAnalytics
import Foundation

/// 사용 통계 — 어느 화면에서 어느 기능을 쓰는지 (Firebase Analytics).
/// 개인정보 없음: 화면 이름·기능 이름·티커·통화 코드만. IDFV·광고 ID 수집은 Info.plist에서 꺼 둠 (ATT 불필요).
/// FirebaseAnalytics import는 이 파일에만 — 나머지 코드는 `Metrics.event(...)` 한 줄.
enum Metrics {
    /// 탭 전환 시 화면 이름 기록 (SwiftUI TabView는 자동 screen_view가 안 잡혀 수동).
    static func screen(_ name: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [AnalyticsParameterScreenName: name])
    }

    /// 기능 터치. 파라미터 값은 문자열만 (티커·통화·탭 이름 등).
    static func event(_ name: String, _ params: [String: String] = [:]) {
        Analytics.logEvent(name, parameters: params.isEmpty ? nil : params)
    }
}
