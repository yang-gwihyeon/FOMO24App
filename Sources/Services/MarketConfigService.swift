import Foundation
import FirebaseFirestore

/// Firestore `config/marketSessions`에서 시장 시간·휴장일을 내려받아
/// MarketSession.all(하드코딩 기본값)을 덮어쓴다.
/// 문서가 없거나 파싱 실패 시 기본값 유지 — 오프라인은 SDK 캐시가 처리.
enum MarketConfigService {
    static func load() async {
        do {
            let snap = try await Firestore.firestore()
                .collection("config").document("marketSessions").getDocument()
            guard let raw = snap.data()?["sessions"] as? [[String: Any]] else { return }
            let sessions = raw.compactMap(MarketSession.init(remote:))
            guard !sessions.isEmpty else { return }
            await MainActor.run { MarketSession.all = sessions }
        } catch {
            // 네트워크 실패 등 — 기본값/캐시 유지
        }
    }
}
