import FOMOCore
import MarketKit
import SwiftUI

struct DashboardView: View {
    @Environment(PriceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// 다이나믹 아일랜드 안내 툴팁 — 추적이 설정돼 있지 않으면 앱 실행마다 표시.
    /// 닫으면 이번 실행 동안만 숨김, 추적을 시작하면 즉시 사라짐.
    @State private var islandTipDismissed = false
    private var showIslandTip: Bool {
        #if DEBUG
        // 스크린샷 자동화용 숨김 플래그 (DEBUG 전용)
        if UserDefaults.standard.bool(forKey: "hideIslandTip") { return false }
        #endif
        // 라이브 액티비티 미지원 기기(구형 아이폰·아이패드 호환 모드)에서는 안내 자체를 숨김
        return LiveActivityManager.shared.isAvailable
            && !islandTipDismissed && LiveActivityManager.shared.trackedTickers.isEmpty
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            content
        }
        .overlay(alignment: .bottom) { toastView }
        .animation(.snappy, value: store.toast)
        // 포그라운드일 때만 5초 폴링, 백그라운드 진입 시 중단 (요구사항).
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:   store.startPolling()
            default:        store.stopPolling()
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = store.toast {
            Label(toast, systemImage: "bolt.heart.fill")
                .font(.pd(14, .semibold, relativeTo: .subheadline))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(hex: 0x191F28), in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation(.snappy) { store.toast = nil }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .failed(let message):
            ErrorView(message: message) { Task { await store.refresh() } }
        case .loaded:
            loadedList
        case .idle:
            LoadingView()
        case .loading:
            if store.quotes.isEmpty { LoadingView() } else { loadedList }
        }
    }

    private var loadedList: some View {
        // 타이틀·통화·정렬 바는 상단 고정, 그 아래 종목 리스트만 스크롤.
        // 풀투리프레시는 리스트에만 → 스피너가 필터 바와 주식 정보 사이에 표시됨.
        VStack(spacing: 0) {
            HeaderView()
            CurrencyPicker()
                .padding(.top, 12)
            SortBar()
                .padding(.top, 14)
                .padding(.bottom, 10)
            Divider()
            List {
                ForEach(store.displayedTickers, id: \.self) { ticker in
                    PriceRowView(ticker: ticker)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color(uiColor: .systemBackground))
                        .listRowSeparatorTint(Color(uiColor: .separator).opacity(0.5))
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 20 }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .refreshable {
                await store.refresh()               // 당겨서 새로고침 (유일한 수동 갱신)
                // 수동 갱신 시 다이나믹 아일랜드 안내 다시 노출
                withAnimation(.snappy) { islandTipDismissed = false }
            }
            .overlay(alignment: .topTrailing) {
                if showIslandTip {
                    IslandTipBubble(lang: store.appLanguage) {
                        withAnimation(.snappy) { islandTipDismissed = true }
                    }
                }
            }
            // 스크롤이 시작되면 툴팁 닫기
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    if showIslandTip { withAnimation(.snappy) { islandTipDismissed = true } }
                }
            )
        }
    }

}

// MARK: - 정렬 (버튼 → 바텀시트)

private struct SortBar: View {
    @Environment(PriceStore.self) private var store
    @State private var showSheet = false
    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        HStack {
            Button {
                Haptics.tap()
                showSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                    Text(store.sortOption.label(lang))
                        .font(.pd(13, .semibold, relativeTo: .subheadline))
                        .fixedSize()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .animation(nil, value: lang)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(updatedText)
                .font(.pd(11, .regular, relativeTo: .caption2))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showSheet) {
            SortSheet().environment(store)
        }
    }

    private var updatedText: String {
        guard let date = store.lastUpdated else { return "" }
        return "\(lang.updatedPrefix) \(Fmt.date("HH:mm:ss").string(from: date))"
    }
}

/// 아래에서 올라오는 정렬 선택 시트.
private struct SortSheet: View {
    @Environment(PriceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lang.sortTitle)
                .font(.pd(18, .bold, relativeTo: .title3))
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            ForEach(Array(PriceStore.SortOption.allCases.enumerated()), id: \.element) { idx, option in
                if idx > 0 { Divider().padding(.leading, 56) }
                row(option)
            }
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    private func row(_ option: PriceStore.SortOption) -> some View {
        let selected = store.sortOption == option
        return Button {
            Haptics.tap()
            store.sortOption = option
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                    .frame(width: 24)
                Text(option.label(lang))
                    .font(.pd(16, selected ? .semibold : .regular, relativeTo: .body))
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 헤더 (제목 + 라이브 상태 + 마지막 갱신 + 새로고침)

private struct HeaderView: View {
    @Environment(PriceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("FOMO24")
                    .font(.pd(28, .bold, relativeTo: .largeTitle))
                livePill
            }
            marketPulse
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var lang: AppLanguage { store.appLanguage }

    /// 제품 정체성 — "24시간 거래 vs 정규장" 상태를 한 줄로.
    private var openMarketCount: Int {
        MarketSession.all.filter { $0.status(at: Date()).phase == .regular }.count
    }

    private var marketPulse: some View {
        let count = openMarketCount
        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(Theme.accent)
            Text(exchangesLabel)
                .font(.pd(12, .semibold, relativeTo: .caption))
                .foregroundStyle(Theme.accent)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(lang.marketPulse(openCount: count))
                .font(.pd(12, .medium, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }
    }

    private var exchangesLabel: String {
        switch lang {
        case .ko: return "4개 거래소 실시간 비교"
        case .ja: return "4取引所リアルタイム比較"
        case .en: return "4 exchanges live"
        }
    }

    private var livePill: some View {
        let green = Color(hex: 0x15C47E)
        return HStack(spacing: 4) {
            Circle()
                .fill(green)
                .frame(width: 7, height: 7)
            Text("LIVE")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(green)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(green.opacity(0.12), in: Capsule())
    }
}

// MARK: - 로딩 / 에러 상태

private struct LoadingView: View {
    @Environment(PriceStore.self) private var store
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(store.appLanguage.loadingText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ErrorView: View {
    @Environment(PriceStore.self) private var store
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: retry) {
                Text(store.appLanguage.t("다시 시도", "Retry"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
    }
}

// MARK: - 다이나믹 아일랜드 안내 툴팁 (최초 1회)

private struct IslandTipBubble: View {
    let lang: AppLanguage
    let dismiss: () -> Void

    private let bubbleColor = Color(hex: 0x191F28)

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(lang.t("실시간 추적", "Live Tracking"))
                .font(.pd(13, .bold, relativeTo: .caption))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            // 아래 방향 꼬리 — 꼭지 끝 바로 아래가 방송 버튼
            Rectangle()
                .fill(bubbleColor)
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(45))
                .offset(y: -7)
                .padding(.trailing, 19)
        }
        .padding(.trailing, 53)
        // 꼬리 끝이 방송 버튼 바로 위에 오도록
        .offset(y: -12)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .onTapGesture { dismiss() }
        .transition(.opacity)
        .zIndex(1)
    }
}

#Preview {
    DashboardView()
        .environment(PriceStore(injected: MockPriceService()))
}
