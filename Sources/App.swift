import FOMOCore
import MarketKit
import SwiftUI
import SwiftData

@main
struct FOMO24App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PriceStore()

    init() {
        AppFont.register()
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .tint(Theme.accent)          // 탭바·컨트롤 토스 블루
                .preferredColorScheme(nil)   // 라이트/다크 모드 자동 대응
        }
        .modelContainer(for: [FomoEntry.self, UserCalendarEvent.self])
    }
}

/// 켜져 있는(=알림 예약할) 거래소 ID 집합. UserDefaults 기반.
/// MarketSession.all(메인 액터 격리)을 읽으므로 함께 격리.
@MainActor
enum AlertSettings {
    static func openAlertEnabled(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: "alertOpen_\(id)")
    }
    static func setOpenAlert(_ id: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "alertOpen_\(id)")
    }
    static var enabledOpenIDs: Set<String> {
        Set(MarketSession.all.map(\.id).filter { openAlertEnabled($0) })
    }
}

struct RootTabView: View {
    @Environment(PriceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var fomoEntries: [FomoEntry]

    // 스크린샷 자동화용 초기 탭 지정 — DEBUG 전용. Release 바이너리에는 포함되지 않음 (App Review 5.6 대응)
    #if DEBUG
    @State private var selectedTab = UserDefaults.standard.integer(forKey: "initialTab")
    #else
    @State private var selectedTab = 0
    #endif
    // 서버 발송 상태 확인이 끝나기 전에 로컬 체크가 중복 알림을 울리지 않도록 잠금
    @State private var firedReconciled = false

    var body: some View {
        let lang = store.appLanguage
        // 강제 업데이트 게이트 — Firestore 플래그가 켜지면 앱 전체를 안내 화면으로 잠금
        Group {
            if UpdateGate.shared.needsUpdate {
                ForceUpdateView(storeURL: UpdateGate.shared.storeURL)
            } else {
                mainTabs(lang: lang)
            }
        }
        .onAppear { UpdateGate.shared.start() }
    }

    private func mainTabs(lang: AppLanguage) -> some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tag(0)
                .tabItem { Label(lang.t("마켓", "Markets"), systemImage: "chart.line.uptrend.xyaxis") }

            FomoView()
                .tabItem { Label("FOMO", systemImage: "bolt.heart") }
                .tag(1)

            InvestCalendarView()
                .tabItem { Label(lang.t("캘린더", "Calendar"), systemImage: "calendar") }
                .tag(2)

            MoreView()
                .tabItem { Label(lang.t("더보기", "More"), systemImage: "ellipsis.circle") }
                .tag(3)
        }
        // 시세가 갱신될 때마다 FOMO 임계값 체크 + 다이나믹 아일랜드 갱신
        .onChange(of: store.lastUpdated) { _, _ in
            checkFomoAlerts()
            LiveActivityManager.shared.updateAll(from: store)
            autoTrackIfNeeded()
        }
        .onAppear {
            LiveActivityManager.shared.restore()
            #if DEBUG
            // 스크린샷 자동화용: -seedDemo YES 로 실행하면 데모 What-if 항목 삽입 (DEBUG 전용)
            if UserDefaults.standard.bool(forKey: "seedDemo") && fomoEntries.isEmpty {
                let demo: [(String, Double, Date)] = [
                    ("NVDA", 175.00, Calendar.current.date(byAdding: .day, value: -30, to: .now)!),
                    ("SKHX", 950.00, Calendar.current.date(byAdding: .day, value: -60, to: .now)!),
                    ("MU",   900.00, Calendar.current.date(byAdding: .day, value: -14, to: .now)!),
                ]
                for (ticker, price, date) in demo {
                    modelContext.insert(FomoEntry(ticker: ticker, savedPriceUSD: price, savedAt: date))
                }
            }
            #endif
        }
        // FOMO 목록이 바뀌면 서버 푸시용 Firestore 동기화
        .onChange(of: fomoEntries.map { "\($0.uuid):\($0.alertPct)" }) { _, _ in syncToServer() }
        // 앱이 켜질 때 개장 알림 재예약 + 서버 동기화
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                // 백그라운드 사이 시스템이 내린 라이브 액티비티를 앱 상태에 반영
                LiveActivityManager.shared.restore()
                Task {
                    // 원격 종목 카탈로그(config/catalog) 반영 — 실패 시 내장 목록 유지
                    await CatalogConfigService.load()
                }
                Task {
                    // 원격 시장시간(config/marketSessions) 반영 후 알림 재예약
                    await MarketConfigService.load()
                    let ids = AlertSettings.enabledOpenIDs
                    // 활성화된 개장 알림이 있을 때만 재예약(불필요한 권한요청 방지)
                    if !ids.isEmpty {
                        await NotificationManager.shared.rescheduleMarketOpens(enabledIDs: ids)
                    }
                }
                firedReconciled = false
                Task {
                    await reconcileFiredAlerts()
                    firedReconciled = true
                }
                syncToServer()
            }
        }
    }

    /// 스크린샷 자동화용: -autoTrack NVDA 로 실행하면 첫 시세 수신 시 다이나믹 아일랜드 추적 시작 (DEBUG 전용).
    private func autoTrackIfNeeded() {
        #if DEBUG
        guard let ticker = UserDefaults.standard.string(forKey: "autoTrack"),
              !LiveActivityManager.shared.isTracking(ticker),
              LiveActivityManager.shared.trackedTickers.isEmpty,
              let quote = store.primary(ticker) else { return }
        LiveActivityManager.shared.toggle(
            ticker: ticker,
            name: Catalog.name(for: ticker, language: store.appLanguage),
            price: quote.usdPrice,
            changePct: quote.change24h)
        #endif
    }

    /// FOMO 알림 설정을 서버(Firestore)에 반영 → Cloud Function이 백그라운드 푸시.
    private func syncToServer() {
        let records = fomoEntries.map {
            AlertRecord(uuid: $0.uuid, ticker: $0.ticker,
                        name: Catalog.name(for: $0.ticker, language: store.appLanguage),
                        savedPrice: $0.savedPriceUSD, alertPct: $0.alertPct)
        }
        FirebaseSync.shared.updateAlerts(records)
    }

    private func checkFomoAlerts() {
        // 서버 발송 상태 확인 전에는 체크하지 않음 — 서버 푸시 직후 앱을 열었을 때 중복 알림 방지
        guard firedReconciled else { return }
        // 1회성 알림: 설정 %에 도달하면 딱 1번 울리고 설정을 기본값(꺼짐)으로 되돌린다.
        for entry in fomoEntries where entry.alertPct > 0 && !entry.hasAlerted {
            guard let usd = store.currentUSDPrice(for: entry.ticker) else { continue }
            let pct = entry.returnPct(currentUSD: usd)
            if abs(pct) >= entry.alertPct {
                NotificationManager.shared.fireFomoAlert(
                    name: Catalog.name(for: entry.ticker, language: store.appLanguage), pct: pct)
                entry.alertPct = 0
                entry.hasAlerted = false
            }
        }
    }

    /// 서버가 발송 완료한 알림을 로컬에도 반영 — 설정을 기본값(꺼짐)으로 되돌린다.
    /// (서버는 발송 시 문서에 hasAlerted=true만 남기므로, 앱 복귀 때 직접 읽어 동기화)
    private func reconcileFiredAlerts() async {
        // 콜드 스타트 직후에는 @Query가 아직 비어 있을 수 있어 DB에서 직접 조회
        let all = (try? modelContext.fetch(FetchDescriptor<FomoEntry>())) ?? []
        let armed = all.filter { $0.alertPct > 0 }
        guard !armed.isEmpty else { return }

        var fired = await FirebaseSync.shared.firedUUIDs(among: armed.map(\.uuid))
        if fired.isEmpty {
            // 푸시 탭 직후 초고속 진입: 서버가 발송 표시를 쓰기 전일 수 있어 2초 뒤 재확인
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            fired = await FirebaseSync.shared.firedUUIDs(among: armed.map(\.uuid))
        }
        guard !fired.isEmpty else { return }
        for entry in armed where fired.contains(entry.uuid) {
            entry.alertPct = 0
            entry.hasAlerted = false
        }
        syncToServer()   // alertPct 0 → 동기화 diff가 서버 문서도 삭제
    }
}
