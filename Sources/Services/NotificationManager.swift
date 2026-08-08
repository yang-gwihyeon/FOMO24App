import FOMOCore
import MarketKit
import Foundation
import UserNotifications

/// 로컬 알림 관리 — 장 개장 예약 알림 + FOMO 임계값 즉시 알림.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
    }

    /// 권한 요청. 이미 허용/거부면 현재 상태 반환.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    // MARK: 장 개장 10분 전 알림 (예약형 — 앱이 꺼져 있어도 발송)

    func rescheduleMarketOpens(enabledIDs: Set<String>, minutesBefore: Int = 10) async {
        guard await requestAuthorization() else { return }
        // 기존 개장 알림 제거
        let pending = await center.pendingNotificationRequests()
        let openIDs = pending.map(\.identifier).filter { $0.hasPrefix("open-") }
        center.removePendingNotificationRequests(withIdentifiers: openIDs)

        let now = Date()
        let lang = AppLanguage.current
        for session in MarketSession.all where enabledIDs.contains(session.id) {
            let opens = session.upcomingRegularOpens(count: 5, from: now)
            for (i, open) in opens.enumerated() {
                let fire = open.addingTimeInterval(TimeInterval(-minutesBefore * 60))
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = lang.t("\(session.flag) \(session.name) 곧 개장",
                                       "\(session.flag) \(session.localizedName(lang)) opening soon")
                content.body = lang.t("정규장 개장 \(minutesBefore)분 전이에요.",
                                      "Regular session opens in \(minutesBefore) minutes.")
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: "open-\(session.id)-\(i)", content: content, trigger: trigger)
                try? await center.add(req)
            }
        }
    }

    func cancelMarketOpens() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("open-") })
    }

    // MARK: FOMO 임계값 알림 (즉시형 — 앱 포그라운드 감지 시)

    func fireFomoAlert(name: String, pct: Double) {
        let up = pct >= 0
        let lang = AppLanguage.current
        let content = UNMutableNotificationContent()
        content.title = up ? lang.t("😭 \(name) 급등", "😭 \(name) surged")
                           : lang.t("😌 \(name) 하락", "😌 \(name) dropped")
        content.body = String(format: lang.t("기록가 대비 %@%.1f%% \(up ? "올랐어요" : "떨어졌어요").",
                                             "%@%.1f%% \(up ? "up" : "down") from your saved price."),
                              up ? "+" : "", pct)
        content.sound = .default
        let req = UNNotificationRequest(identifier: "fomo-\(name)-\(Int(pct))", content: content, trigger: nil)
        center.add(req)
    }

    // 앱이 켜져 있을 때도 배너 표시
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
