import Foundation
import Observation
import FirebaseFirestore

/// Firestore `config/appUpdate` 실시간 감시 — 강제 업데이트 게이트.
/// { force: Bool, minVersion: "1.1", storeUrl: "https://apps.apple.com/..." }
/// force가 켜져 있고 현재 버전 < minVersion이면 앱 전체를 업데이트 안내 화면으로 잠근다.
/// 실시간 리스너라서 콘솔에서 플래그를 켜고 끄면 실행 중인 앱에도 즉시 반영.
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
        Firestore.firestore().collection("config").document("appUpdate")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let data = snap?.data() else { return }
                let force = data["force"] as? Bool ?? false
                let minVersion = data["minVersion"] as? String ?? "0"
                if let url = (data["storeUrl"] as? String).flatMap(URL.init(string:)) {
                    Task { @MainActor in self.storeURL = url }
                }
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                let needs = force && Self.isVersion(current, lowerThan: minVersion)
                Task { @MainActor in self.needsUpdate = needs }
            }
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
