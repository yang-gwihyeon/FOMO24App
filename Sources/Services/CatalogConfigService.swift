import FOMOCore
import Foundation
import FirebaseFirestore

/// Firestore `config/catalog`에서 종목 목록을 내려받아 Catalog(내장 기본값)를 덮어쓴다.
/// 문서가 없거나 파싱 실패 시 기본값 유지 — 오프라인은 SDK 캐시가 처리.
/// → 종목 추가/삭제/이름 변경은 앱 업데이트 없이 문서 수정만으로 전 사용자 반영.
enum CatalogConfigService {
    static func load() async {
        do {
            let snap = try await Firestore.firestore()
                .collection("config").document("catalog").getDocument()
            guard let raw = snap.data()?["entries"] as? [[String: Any]] else { return }
            let entries = raw.compactMap(Catalog.Entry.init(remote:))
            guard !entries.isEmpty else { return }
            Catalog.apply(entries)
        } catch {
            // 네트워크 실패 등 — 기본값/캐시 유지
        }
    }
}
