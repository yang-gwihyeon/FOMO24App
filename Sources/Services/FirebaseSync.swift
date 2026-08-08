import Foundation
import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseFirestore

/// FOMO 알림 1건을 서버로 보낼 최소 정보.
struct AlertRecord {
    let uuid: String
    let ticker: String
    let name: String
    let savedPrice: Double
    let alertPct: Double
}

/// Firebase 연동 — FCM 토큰 수신 + FOMO 알림을 Firestore `alerts`에 동기화.
/// 서버(Cloud Function)가 이 컬렉션을 읽어 가격 도달 시 푸시를 보낸다.
@MainActor
final class FirebaseSync: NSObject, MessagingDelegate {
    static let shared = FirebaseSync()

    private(set) var fcmToken: String?
    private var latest: [AlertRecord] = []

    func start() {
        Messaging.messaging().delegate = self
        // 유저 권한과 무관하게 APNs 토큰을 받아 FCM 등록
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// FOMO 목록이 바뀌거나 앱이 활성화될 때 호출. 토큰 있으면 즉시 반영.
    func updateAlerts(_ records: [AlertRecord]) {
        latest = records
        sync()
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        self.fcmToken = fcmToken
        sync()
    }

    /// 마지막으로 서버에 올렸던 알림 uuid 목록 — 로컬에서 기록이 삭제되면
    /// 이 목록과 대조해 서버 문서도 지운다 (고아 문서 방지).
    private static let syncedKey = "fomoSyncedAlertUUIDs"

    private func sync() {
        guard let token = fcmToken else { return }   // 토큰 없으면 다음 기회에
        let db = Firestore.firestore()
        let col = db.collection("alerts")

        let active = latest.filter { $0.alertPct > 0 }
        let activeUUIDs = Set(active.map(\.uuid))
        let previous = Set(UserDefaults.standard.stringArray(forKey: Self.syncedKey) ?? [])

        // 이전에 올렸지만 지금은 없는(삭제됐거나 알림 끈) 문서 정리
        for uuid in previous.subtracting(activeUUIDs) {
            col.document("\(token)_\(uuid)").delete()
        }
        // 현재 켜져 있는 알림 반영 — hasAlerted는 서버가 관리하므로 merge
        for r in active {
            col.document("\(token)_\(r.uuid)").setData([
                "fcmToken": token,
                "ticker": r.ticker,
                "name": r.name,
                "savedPrice": r.savedPrice,
                "alertPct": r.alertPct,
                "lang": AppLanguage.current == .ko ? "ko" : "en"   // 푸시 문구 언어
            ], merge: true)
        }
        UserDefaults.standard.set(Array(activeUUIDs), forKey: Self.syncedKey)
    }

    /// 서버가 이미 발송 완료(hasAlerted)한 알림의 uuid 목록.
    /// 앱 복귀 시 로컬 알림 설정을 기본값(꺼짐)으로 되돌리는 데 사용.
    func firedUUIDs(among uuids: [String]) async -> [String] {
        // 콜드 스타트에는 델리게이트 콜백보다 먼저 호출됨 — 토큰을 직접 조회 (캐시라 빠름)
        if fcmToken == nil {
            fcmToken = try? await Messaging.messaging().token()
        }
        guard let token = fcmToken, !uuids.isEmpty else { return [] }
        let col = Firestore.firestore().collection("alerts")
        var fired: [String] = []
        for uuid in uuids {
            if let doc = try? await col.document("\(token)_\(uuid)").getDocument(),
               doc.data()?["hasAlerted"] as? Bool == true {
                fired.append(uuid)
            }
        }
        return fired
    }
}

/// Firebase 초기화 + APNs 토큰 브리지.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Firebase 로그 최소화 — Xcode(특히 무선) 연결 시 콘솔 로그 폭주가
        // 메인 스레드를 멈추게 하는 것을 완화
        FirebaseConfiguration.shared.setLoggerLevel(.min)
        FirebaseApp.configure()
        Task { @MainActor in FirebaseSync.shared.start() }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}
