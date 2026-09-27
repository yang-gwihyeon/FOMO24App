import FOMOCore
import Foundation

/// Firestore `config/catalog`에서 종목 목록을 내려받아 Catalog(내장 기본값)를 덮어쓴다.
/// 문서가 없거나 파싱 실패 시 기본값 유지 — 오프라인은 `FirestoreREST` 파일 캐시가 처리 (ADR-0009).
/// → 종목 추가/삭제/이름 변경은 앱 업데이트 없이 문서 수정만으로 전 사용자 반영.
enum CatalogConfigService {
    static func load() async {
        guard let doc = await FirestoreREST.shared.getDocumentCached("config/catalog"),
              let raw = doc["entries"] as? [[String: Any]] else { return }   // 네트워크·캐시 모두 없음 → 기본값
        let entries = raw.compactMap(Catalog.Entry.init(remote:))
        guard !entries.isEmpty else { return }
        Catalog.apply(entries)
    }
}
