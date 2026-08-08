import Foundation
import SwiftData

/// "샀다 치고" 기록 한 건. 실제 매수가 아니라 가상 기준가를 저장해
/// 현재가와 비교해 포모(올랐을 때)/역포모(떨어졌을 때)를 보여준다.
/// 거래를 중개하지 않는 순수 개인 기록 기능.
@Model
final class FomoEntry {
    /// 가격 알림을 켤 수 있는 최대 기록 수 (서버 푸시 부하·스팸 방지)
    static let maxAlertCount = 3

    var ticker: String          // 예: "NVDA"
    var savedPriceUSD: Double    // 기록 시점 가격 (USD 기준)
    var savedAt: Date            // 기록한 날짜·시간
    var memo: String
    var alertPct: Double         // 알림 임계값(%). 0이면 끔. 도달 시 딱 1번 발송
    var hasAlerted: Bool         // 발송 완료 여부 — 재설정해야 다시 발송 가능
    var alertedAbs: Double = 0   // (구버전 필드, 미사용 — 마이그레이션 안전용)
    var uuid: String             // Firestore 문서 ID용 안정 식별자

    init(ticker: String, savedPriceUSD: Double, savedAt: Date = .now, memo: String = "", alertPct: Double = 0) {
        self.ticker = ticker
        self.savedPriceUSD = savedPriceUSD
        self.savedAt = savedAt
        self.memo = memo
        self.alertPct = alertPct
        self.hasAlerted = false
        self.uuid = UUID().uuidString
    }

    /// 현재가 대비 수익률(%). 양수=포모, 음수=역포모.
    func returnPct(currentUSD: Double) -> Double {
        guard savedPriceUSD > 0 else { return 0 }
        return (currentUSD / savedPriceUSD - 1) * 100
    }
}
