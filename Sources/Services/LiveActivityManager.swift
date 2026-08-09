import FOMOCore
import MarketKit
import Foundation
import ActivityKit
import Observation
import FirebaseFirestore

/// 다이나믹 아일랜드 실시간 가격 추적 관리.
/// 앱이 포그라운드일 때 5초 폴링에 맞춰 갱신되고, 백그라운드로 가도
/// 아일랜드/잠금화면에 마지막 가격이 유지된다 (시스템 최대 8시간).
@MainActor
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// ticker → 실행 중인 액티비티
    @ObservationIgnored private var activities: [String: Activity<PriceActivityAttributes>] = [:]
    private(set) var trackedTickers: Set<String> = []

    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func isTracking(_ ticker: String) -> Bool {
        trackedTickers.contains(ticker)
    }

    /// 앱 시작/복귀 시 시스템 상태를 진실로 삼아 동기화.
    /// 시스템이 내린 액티비티(8시간 한도·사용자 제거·stale 회수)는 앱 상태에서도 제거한다.
    func restore() {
        let alive = Activity<PriceActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
        let aliveByTicker = Dictionary(alive.map { ($0.attributes.ticker, $0) },
                                       uniquingKeysWith: { a, _ in a })
        // 시스템에서 사라진 추적은 해제 (+ 서버 푸시 토큰 정리)
        for ticker in activities.keys where aliveByTicker[ticker] == nil {
            activities[ticker] = nil
            if let token = pushTokens.removeValue(forKey: ticker) {
                Firestore.firestore().collection("laTokens").document(token).delete()
            }
        }
        // 시스템에는 있는데 앱이 모르는 액티비티는 채택
        for (ticker, activity) in aliveByTicker where activities[ticker] == nil {
            activities[ticker] = activity
            syncPushToken(for: activity)
            watchState(for: activity)
        }
        trackedTickers = Set(activities.keys)
    }

    /// 액티비티가 종료/제거되는 순간 앱 상태에서도 내린다 (앱이 켜져 있을 때 실시간 반영).
    private func watchState(for activity: Activity<PriceActivityAttributes>) {
        let ticker = activity.attributes.ticker
        let id = activity.id
        Task {
            for await state in activity.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                // 같은 티커로 새 액티비티가 시작됐을 수 있으니 id가 일치할 때만 제거
                if self.activities[ticker]?.id == id {
                    self.activities[ticker] = nil
                    self.trackedTickers.remove(ticker)
                    if let token = self.pushTokens.removeValue(forKey: ticker) {
                        try? await Firestore.firestore().collection("laTokens").document(token).delete()
                    }
                }
            }
        }
    }

    func toggle(ticker: String, name: String, price: Double, changePct: Double) {
        if isTracking(ticker) {
            end(ticker: ticker)
        } else {
            start(ticker: ticker, name: name, price: price, changePct: changePct)
        }
    }

    private func start(ticker: String, name: String, price: Double, changePct: Double) {
        guard isAvailable else { return }
        // 한 번에 1종목만 — 새 추적 시작 시 기존 액티비티 종료
        for existing in trackedTickers { end(ticker: existing) }
        let attributes = PriceActivityAttributes(ticker: ticker, name: name)
        let state = PriceActivityAttributes.ContentState(
            price: price, changePct: changePct, updatedAt: Date.now.timeIntervalSince1970)
        do {
            // pushType .token → 서버가 APNs로 직접 갱신 (앱 꺼져도 1분마다)
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date(timeIntervalSinceNow: 300)),
                pushType: .token
            )
            activities[ticker] = activity
            trackedTickers.insert(ticker)
            syncPushToken(for: activity)
            watchState(for: activity)
        } catch {
            // 라이브 액티비티 한도 초과 등 — 조용히 무시
        }
    }

    /// 액티비티의 push 토큰을 Firestore에 등록 (회전 시 갱신) — 서버 푸시용.
    private func syncPushToken(for activity: Activity<PriceActivityAttributes>) {
        let ticker = activity.attributes.ticker
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                let old = pushTokens[ticker]
                pushTokens[ticker] = token
                let col = Firestore.firestore().collection("laTokens")
                if let old, old != token { try? await col.document(old).delete() }
                try? await col.document(token).setData([
                    "token": token,
                    "ticker": ticker,
                    "startedAt": FieldValue.serverTimestamp()
                ])
            }
        }
    }

    @ObservationIgnored private var pushTokens: [String: String] = [:]

    func end(ticker: String) {
        guard let activity = activities[ticker] else { return }
        activities[ticker] = nil
        trackedTickers.remove(ticker)
        if let token = pushTokens.removeValue(forKey: ticker) {
            Firestore.firestore().collection("laTokens").document(token).delete()
        }
        // Activity는 non-Sendable이지만 ActivityKit API는 어느 컨텍스트에서든 호출 가능
        nonisolated(unsafe) let act = activity
        Task.detached {
            await act.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 시세 갱신 때마다 호출 — 추적 중인 종목들의 아일랜드 가격을 업데이트.
    func updateAll(from store: PriceStore) {
        guard !activities.isEmpty else { return }
        for (ticker, activity) in activities {
            guard let quote = store.primary(ticker) else { continue }
            let state = PriceActivityAttributes.ContentState(
                price: quote.usdPrice, changePct: quote.change24h,
                updatedAt: Date.now.timeIntervalSince1970)
            // Activity는 non-Sendable이지만 ActivityKit API는 어느 컨텍스트에서든 호출 가능
            nonisolated(unsafe) let act = activity
            Task.detached {
                await act.update(.init(state: state, staleDate: Date(timeIntervalSinceNow: 300)))
            }
        }
    }
}
