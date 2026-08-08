import SwiftUI
import SwiftData
import PhosphorSwift

/// FOMO 트래커 탭 — "샀다 치고" 기록 목록.
struct FomoView: View {
    @Environment(PriceStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \FomoEntry.savedAt, order: .reverse) private var entries: [FomoEntry]

    @State private var showingAdd = false
    @State private var alertTarget: FomoEntry?      // 알림 % 입력 대상
    @State private var alertInput = ""
    @State private var showLimitAlert = false

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page.ignoresSafeArea()
                if entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(lang.fomoTabTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showingAdd = true
                    } label: {
                        Ph.plusCircle.fill
                            .color(Theme.accent)
                            .frame(width: 26, height: 26)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddFomoSheet()
                    .environment(store)
            }
            // 컨텍스트 메뉴 → 알림 % 직접 입력 (1% 단위)
            .alert(lang.t("가격 알림 설정", "Set Price Alert"), isPresented: Binding(
                get: { alertTarget != nil },
                set: { if !$0 { alertTarget = nil } }
            )) {
                TextField(lang.t("예: 5", "e.g. 5"), text: $alertInput)
                    .keyboardType(.numberPad)
                Button(lang.t("설정", "Set")) { applyAlertInput() }
                Button(lang.t("취소", "Cancel"), role: .cancel) {}
            } message: {
                Text(lang.t("몇 %에 도달하면 알려드릴까요? (1% 단위, 0 = 끔)\n도달 시 딱 1번만 알림이 와요. 다시 받으려면 재설정하세요.",
                            "At what % move should we notify you? (whole %, 0 = off)\nYou'll get exactly one alert. Re-set it to get another."))
            }
            .alert(lang.t("가격 알림은 최대 \(FomoEntry.maxAlertCount)개", "Up to \(FomoEntry.maxAlertCount) price alerts"), isPresented: $showLimitAlert) {
                Button(lang.t("확인", "OK"), role: .cancel) {}
            } message: {
                Text(lang.t("이미 \(FomoEntry.maxAlertCount)개 기록에 알림이 켜져 있어요. 다른 기록의 알림을 먼저 꺼주세요.",
                            "Alerts are already on for \(FomoEntry.maxAlertCount) entries. Turn one off first."))
            }
        }
    }

    private var list: some View {
        // List = 셀 재사용 + 네이티브 스와이프 액션
        List {
            ForEach(entries) { entry in
                FomoRowView(entry: entry, onBellTap: {
                    Haptics.tap()
                    alertInput = entry.alertPct > 0 ? "\(Int(entry.alertPct))" : ""
                    alertTarget = entry
                })
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            delete(entry)
                        } label: {
                            // 스와이프 액션 아이콘은 SF Symbol만 크기가 안정적 (Phosphor는 frame 무시)
                            Label(lang.t("삭제", "Delete"), systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Section(lang.t("가격 알림", "Price Alert")) {
                            Button {
                                Haptics.tap()
                                alertInput = entry.alertPct > 0 ? "\(Int(entry.alertPct))" : ""
                                alertTarget = entry
                            } label: {
                                Label(entry.alertPct > 0
                                      ? lang.t("알림 변경 (현재 ±\(Int(entry.alertPct))%)", "Change alert (now ±\(Int(entry.alertPct))%)")
                                      : lang.t("알림 설정…", "Set alert…"),
                                      systemImage: "bell")
                            }
                            if entry.alertPct > 0 {
                                Button {
                                    setAlert(entry, 0)
                                } label: {
                                    Label(lang.t("알림 끄기", "Turn off alert"), systemImage: "bell.slash")
                                }
                            }
                        }
                    }
            }
            // 알림 규칙 안내 (더보기에서 이동)
            Text(lang.t("💡 종목의 알림 버튼을 누르고 목표 등락률(1% 단위)을 설정하면, 기록 가격에서 그 %에 도달할 때 딱 1번 푸시가 와요. 앱이 꺼져 있어도 옵니다. 다시 받으려면 재설정하세요. 최대 \(FomoEntry.maxAlertCount)개까지.",
                        "💡 Tap an entry's alert button and set a target % (whole numbers) — you'll get exactly one push when the price moves that far from your saved price, even with the app closed. Re-set to get another. Up to \(FomoEntry.maxAlertCount) alerts."))
                .font(.pd(11, .regular, relativeTo: .caption2))
                .foregroundStyle(.tertiary)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 16, trailing: 24))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Ph.heartbeat.duotone
                .color(Theme.accent)
                .frame(width: 64, height: 64)
            Text(lang.fomoEmptyText)
                .font(.pd(14, .regular, relativeTo: .subheadline))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                Haptics.tap()
                showingAdd = true
            } label: {
                HStack(spacing: 6) {
                    Ph.plus.bold.color(.white).frame(width: 14, height: 14)
                    Text(lang.t("기록 추가", "Add Entry"))
                }
                    .font(.pd(14, .semibold, relativeTo: .subheadline))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
    }

    private func delete(_ entry: FomoEntry) {
        Haptics.tap()
        context.delete(entry)
    }

    private func setAlert(_ entry: FomoEntry, _ pct: Double) {
        Haptics.tap()
        entry.alertPct = pct
        entry.hasAlerted = false   // 재설정하면 다시 1회 발송 가능
        if pct > 0 { Task { await NotificationManager.shared.requestAuthorization() } }
    }

    /// 입력된 %를 검증(1% 단위, 최대 개수)하고 적용.
    private func applyAlertInput() {
        guard let entry = alertTarget else { return }
        let pct = Double(Int(alertInput.filter(\.isNumber)) ?? 0)
        alertTarget = nil
        if pct > 0 {
            let othersOn = entries.filter { $0.alertPct > 0 && $0 !== entry }.count
            if othersOn >= FomoEntry.maxAlertCount {
                showLimitAlert = true
                return
            }
        }
        setAlert(entry, pct)
    }
}
