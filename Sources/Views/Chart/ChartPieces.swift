import FOMOCore
import SwiftUI

/// 기간 최저~최고 범위에서 현재가 위치를 점 하나로 보여주는 막대.
struct RangePositionBar: View {
    let stats: PriceRangeStats
    let color: Color
    let lang: AppLanguage
    let formatPrice: (Double) -> String

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let x = geo.size.width * min(max(stats.position, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                    Capsule().fill(color.opacity(0.35)).frame(width: max(x, 6))
                    Circle()
                        .fill(color)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .offset(x: min(max(x - 7, 0), geo.size.width - 14))
                }
            }
            .frame(height: 14)
            HStack {
                Text("\(lang.t("최저", "Low")) \(formatPrice(stats.low))")
                Spacer()
                Text("\(lang.t("최고", "High")) \(formatPrice(stats.high))")
            }
            .font(.pd(11, .medium, relativeTo: .caption2).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)   // 같은 내용을 헤드라인 문장이 읽어준다
    }
}

/// 거래소별 현재가를 한 줄 막대로 비교. 막대 길이 = 최저가 대비 얼마나 비싼지.
struct ExchangeCompareView: View {
    let ticker: String
    @Environment(PriceStore.self) private var store

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        let quotes = store.sources(for: ticker)
        let sources = DataSource.allCases.filter { quotes[$0] != nil }
        let prices = quotes.values.map(\.usdPrice)
        let lo = prices.min() ?? 0
        let hi = prices.max() ?? 0

        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("거래소별 현재가", "Price by exchange"))
                .font(.pd(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            ForEach(sources) { source in
                if let price = quotes[source]?.usdPrice {
                    row(source, price: price, lo: lo, hi: hi, showBest: sources.count > 1)
                }
            }
        }
    }

    private func row(_ source: DataSource, price: Double, lo: Double, hi: Double, showBest: Bool) -> some View {
        let isBest = showBest && price == lo
        let fraction = hi > lo ? (price - lo) / (hi - lo) : 0
        let diff = lo > 0 ? (price / lo - 1) * 100 : 0
        return HStack(spacing: 10) {
            Text(source.displayName)
                .font(.pd(13, isBest ? .semibold : .medium, relativeTo: .subheadline))
                .foregroundStyle(isBest ? Theme.accent : .secondary)
                .frame(width: 88, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                    Capsule()
                        .fill(isBest ? Theme.accent : Color.secondary.opacity(0.45))
                        .frame(width: max(geo.size.width * fraction, 6))
                }
            }
            .frame(height: 6)
            Text(store.formatted(price))
                .font(.pd(13, .semibold, relativeTo: .subheadline).monospacedDigit())
            Text(isBest ? lang.t("최저", "Best") : String(format: "+%.2f%%", diff))
                .font(.pd(11, .semibold, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(isBest ? Theme.accent : .secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 기간 선택 (1일 / 1주 / 1달 / 3달).
struct ChartRangePicker: View {
    @Binding var range: ChartRange
    let lang: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ChartRange.allCases) { option in
                let selected = option == range
                Button {
                    guard !selected else { return }
                    Haptics.tap()
                    range = option
                } label: {
                    Text(option.label(lang))
                        .font(.pd(13, selected ? .bold : .medium, relativeTo: .subheadline))
                        .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? AnyShapeStyle(Color(uiColor: .label)) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chart.range.\(option.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// 실시간 연결 상태 — 끊겨서 선이 멈춘 것과 가격이 안 움직이는 것을 구분해 준다.
struct ChartLivePill: View {
    let connected: Bool
    let lang: AppLanguage

    var body: some View {
        let color = connected ? Color(hex: 0x15C47E) : Color.secondary
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(connected ? "LIVE" : lang.t("연결 중", "Connecting"))
                .font(.pd(10, .bold, relativeTo: .caption2))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// 봉 조회 실패 — 차트 자리에만 재시도 버튼 (현재가·거래소 비교는 그대로 보인다).
struct ChartFailedView: View {
    let lang: AppLanguage
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(lang.t("차트를 불러오지 못했어요", "Couldn't load the chart"))
                .font(.pd(14, .medium, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            Button {
                Haptics.tap()
                retry()
            } label: {
                Text(lang.t("다시 시도", "Retry"))
                    .font(.pd(13, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
