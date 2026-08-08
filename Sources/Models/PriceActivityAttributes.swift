import Foundation
import ActivityKit

/// 다이나믹 아일랜드/잠금화면 라이브 액티비티 — 종목 1개의 실시간 가격.
/// 앱 타겟과 위젯 익스텐션 양쪽에 컴파일됨 (구조 변경 시 둘 다 재빌드).
struct PriceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var price: Double        // USD
        var changePct: Double    // 24h %
        var updatedAt: Double    // unix 초 — 서버(APNs) JSON과 호환 위해 Date 대신 Double
    }

    var ticker: String           // 예: "NVDA"
    var name: String             // 표시명 (시작 시점 언어 기준)
}
