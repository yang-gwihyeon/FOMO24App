import FOMOCore
import MarketKit
import Foundation

/// Firestore `config/marketSessions`에서 시장 시간·휴장일을 내려받아
/// MarketSession.all(하드코딩 기본값)을 덮어쓴다.
/// 문서가 없거나 파싱 실패 시 기본값 유지 — 오프라인은 `FirestoreREST` 파일 캐시가 처리 (ADR-0009).
enum MarketConfigService {
    static func load() async {
        guard let doc = await FirestoreREST.shared.getDocumentCached("config/marketSessions"),
              let raw = doc["sessions"] as? [[String: Any]] else { return }   // 네트워크·캐시 모두 없음 → 기본값
        let sessions = raw.compactMap(MarketSession.init(remote:))
        guard !sessions.isEmpty else { return }
        await MainActor.run { MarketSession.all = sessions }
    }
}
