import FOMOCore
import Foundation

/// Firestore `config/fomoShowcase`에서 FOMO 탭 쇼케이스 카드 목록을 내려받는다.
/// 문서가 없거나 파싱 실패 시 빈 배열 → 섹션 자체가 숨겨진다 (문서 삭제 = 기능 끄기).
/// 오프라인은 `FirestoreREST` 파일 캐시가 처리 (ADR-0009).
enum ShowcaseConfigService {
    static func load() async -> [ShowcaseItem] {
        guard let doc = await FirestoreREST.shared.getDocumentCached("config/fomoShowcase"),
              let raw = doc["entries"] as? [[String: Any]] else { return [] }
        return raw.compactMap(ShowcaseItem.init(remote:))
    }
}
