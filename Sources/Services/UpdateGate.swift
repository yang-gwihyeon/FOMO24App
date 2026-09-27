import Foundation
import Observation

/// Firestore `config/appUpdate` 감시 — 강제 업데이트 게이트.
/// { force: Bool, minVersion: "1.1", storeUrl: "https://apps.apple.com/..." }
/// force가 켜져 있고 현재 버전 < minVersion이면 앱 전체를 업데이트 안내 화면으로 잠근다.
/// SDK 실시간 리스너 대신 앱 시작·활성화 때 REST로 읽는다 (ADR-0009) — 콘솔 플래그는 다음 포그라운드 진입 시 반영.
@MainActor
@Observable
final class UpdateGate {
    static let shared = UpdateGate()
    private init() {}

    private(set) var needsUpdate = false
    private(set) var storeURL = URL(string: "https://apps.apple.com")!

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        refresh()
    }

    /// 앱이 활성화될 때마다 호출. 실패(오프라인)하면 마지막 상태 유지.
    func refresh() {
        Task { await load() }
    }

    private func load() async {
        guard let data = try? await FirestoreREST.shared.getDocument("config/appUpdate") else { return }
        let force = data["force"] as? Bool ?? false
        let minVersion = data["minVersion"] as? String ?? "0"
        if let url = (data["storeUrl"] as? String).flatMap(URL.init(string:)) {
            storeURL = url
        }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        needsUpdate = force && Self.isVersion(current, lowerThan: minVersion)
    }

    /// "1.0.2" < "1.1" 같은 세그먼트 단위 버전 비교.
    static func isVersion(_ current: String, lowerThan target: String) -> Bool {
        let c = current.split(separator: ".").compactMap { Int($0) }
        let t = target.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(c.count, t.count) {
            let cv = i < c.count ? c[i] : 0
            let tv = i < t.count ? t[i] : 0
            if cv < tv { return true }
            if cv > tv { return false }
        }
        return false
    }
}
