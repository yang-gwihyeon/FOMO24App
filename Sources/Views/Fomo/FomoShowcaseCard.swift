import FOMOCore
import SwiftUI

/// FOMO 탭 상단 쇼케이스 카드 — "이벤트 직전/직후에 샀다면 지금 몇 %" 훅.
/// 기록이 없는 유저에게도 FOMO를 보여주기 위해 빈 화면에서도 노출된다.
struct FomoShowcaseCard: View {
    let item: ShowcaseItem
    @Environment(PriceStore.self) private var store

    private var lang: AppLanguage { store.appLanguage }
    private var pct: Double? {
        store.currentUSDPrice(for: item.ticker).map(item.returnPct(currentUSD:))
    }

    var body: some View {
        let up = (pct ?? 0) >= 0
        let color = pct == nil ? Color.secondary : Theme.changeColor(up)

        VStack(alignment: .leading, spacing: 7) {
            Text(item.event(lang))
                .font(.pd(11, .medium, relativeTo: .caption2))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            Text(Catalog.name(for: item.ticker, language: lang))
                .font(.pd(14, .semibold, relativeTo: .subheadline))
                .lineLimit(1)
            Text(signedPct(pct))
                .font(.pd(24, .bold, relativeTo: .title2).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(lang.t("그때 샀다면 지금", "If you'd bought then"))
                .font(.pd(10, .medium, relativeTo: .caption2))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            // 기록 행과 구분되는 시그니처 — 수익률 색 테두리
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)   // VoiceOver: 카드 1장을 한 문장으로
    }
}

/// "+34.2%" / "-20.0%" / 시세 없음 "—". 카드·시트 행이 같은 문구를 쓴다.
private func signedPct(_ pct: Double?) -> String {
    pct.map { String(format: "%@%.1f%%", $0 >= 0 ? "+" : "", $0) } ?? "—"
}

/// 가로 슬라이드 — 카드 3장 + (4장 이상이면) "더보기" 카드. Firestore 구성이 비어 있으면 아무것도 그리지 않는다.
/// 좌우 여백은 List 행 inset 대신 contentMargins로 줘서 카드가 화면 가장자리까지 흐른다.
struct FomoShowcaseRow: View {
    @Environment(PriceStore.self) private var store
    @State private var showingAll = false

    var body: some View {
        let (featured, hiddenCount) = ShowcaseItem.split(store.showcaseItems)
        if !featured.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.spacing) {
                    ForEach(featured) { item in
                        FomoShowcaseCard(item: item)
                            .containerRelativeFrame(.horizontal, Self.cardWidth)
                    }
                    if hiddenCount > 0 {
                        FomoShowcaseMoreCard(hiddenCount: hiddenCount) { showingAll = true }
                            .containerRelativeFrame(.horizontal, Self.cardWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .accessibilityIdentifier("showcase.slide")   // UI 스모크 테스트가 스와이프할 대상
            .sheet(isPresented: $showingAll) {
                FomoShowcaseSheet()
                    .environment(store)
            }
        }
    }

    private static let spacing: CGFloat = 10
    /// 카드 2장 + 다음 카드 끝자락이 보이는 너비 — "옆으로 넘길 수 있다"는 힌트.
    private static func cardWidth(_ container: CGFloat, _: Axis) -> CGFloat {
        (container - spacing) / 2.2
    }
}

/// 슬라이드 마지막 "더보기" 카드 — 접힌 개수를 보여주고 탭하면 전체 목록 바텀시트.
struct FomoShowcaseMoreCard: View {
    let hiddenCount: Int
    let action: () -> Void
    @Environment(PriceStore.self) private var store

    var body: some View {
        let lang = store.appLanguage
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Text("+\(hiddenCount)")
                    .font(.pd(24, .bold, relativeTo: .title2).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Text(lang.t("더보기", "See more"))
                    .font(.pd(12, .medium, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                PhIcon(.arrowRightBold, color: Theme.accent)
                    .frame(width: 14, height: 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang.t("쇼케이스 \(hiddenCount)개 더보기", "See \(hiddenCount) more"))
        .accessibilityIdentifier("showcase.more")
    }
}

/// 쇼케이스 전체 목록 바텀시트 — 슬라이드에 못 실은 항목까지 (최대 `ShowcaseItem.maxCount`).
struct FomoShowcaseSheet: View {
    @Environment(PriceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.page.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(store.showcaseItems.prefix(ShowcaseItem.maxCount))) { item in
                            FomoShowcaseListRow(item: item)
                        }
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("showcase.sheet")
            }
            .navigationTitle(lang.t("그때 샀다면 지금", "If you'd bought then"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang.t("닫기", "Close")) { dismiss() }
                        .accessibilityIdentifier("showcase.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// 시트 한 행 — 왼쪽 종목·이벤트, 오른쪽 수익률. 카드와 같은 색 규칙.
struct FomoShowcaseListRow: View {
    let item: ShowcaseItem
    @Environment(PriceStore.self) private var store

    var body: some View {
        let lang = store.appLanguage
        let pct = store.currentUSDPrice(for: item.ticker).map(item.returnPct(currentUSD:))
        let color = pct == nil ? Color.secondary : Theme.changeColor((pct ?? 0) >= 0)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Catalog.name(for: item.ticker, language: lang))
                    .font(.pd(14, .semibold, relativeTo: .subheadline))
                    .lineLimit(1)
                Text(item.event(lang))
                    .font(.pd(11, .medium, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(signedPct(pct))
                .font(.pd(18, .bold, relativeTo: .title3).monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
