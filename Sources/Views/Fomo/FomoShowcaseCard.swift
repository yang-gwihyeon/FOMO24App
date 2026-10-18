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
            Text(pct.map { String(format: "%@%.1f%%", $0 >= 0 ? "+" : "", $0) } ?? "—")
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
    }
}

/// 한 줄에 카드 2장 — Firestore 구성이 비어 있으면 아무것도 그리지 않는다.
struct FomoShowcaseRow: View {
    @Environment(PriceStore.self) private var store

    var body: some View {
        let items = Array(store.showcaseItems.prefix(2))
        if !items.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                ForEach(items) { FomoShowcaseCard(item: $0) }
            }
        }
    }
}
