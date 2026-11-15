import Charts
import FOMOCore
import SwiftUI

/// 차트에 찍는 FOMO 기록 한 건.
struct ChartEntryMark: Identifiable, Hashable {
    let id: String
    /// 기록 시점이 기간보다 앞이면 왼쪽 끝으로 당겨 놓은 값
    let date: Date
    let usd: Double
    let isSelected: Bool
}

/// 차트 x축에 표시하는 캘린더 일정.
struct ChartEventMark: Identifiable, Hashable {
    let id: String
    let date: Date
    let icon: String
}

/// 선 하나 + 이 앱만의 겹침 정보(정규장 띠 · FOMO 기록 · 일정)만 그리는 차트 본체.
/// 캔들·보조지표는 의도적으로 넣지 않는다.
struct PriceChartView: View {
    let points: [ChartPoint]
    let bands: [DateInterval]
    let entries: [ChartEntryMark]
    let events: [ChartEventMark]
    let pinned: ChartPoint?
    let lineColor: Color
    /// 선택된 기록의 손익 색 (기록가~현재가 사이 채움)
    let fillColor: Color
    let range: ChartRange
    let lang: AppLanguage
    let formatPrice: (Double) -> String
    @Binding var scrubDate: Date?

    /// 선택된 기록 중 차트에 겹쳐 그릴 것. 기록가가 선의 범위에서 너무 멀면(실시간 5분 창에 며칠 전 기록 등)
    /// 축을 거기까지 늘리는 순간 선이 납작한 직선이 되므로 겹치지 않는다 — 수익률은 아래 칩에 그대로 나온다.
    private var selected: ChartEntryMark? {
        guard let entry = entries.first(where: \.isSelected),
              let lo = points.map(\.usd).min(), let hi = points.map(\.usd).max() else { return nil }
        let span = max(hi - lo, hi * 0.002)
        return ((lo - span)...(hi + span)).contains(entry.usd) ? entry : nil
    }

    private var yDomain: ClosedRange<Double> {
        var lo = points.map(\.usd).min() ?? 0
        var hi = points.map(\.usd).max() ?? 1
        if let selected {
            lo = min(lo, selected.usd)
            hi = max(hi, selected.usd)
        }
        let pad = max((hi - lo) * 0.08, hi * 0.001)
        return (lo - pad)...(hi + pad)
    }

    private var xDomain: ClosedRange<Date> {
        let first = points.first?.date ?? .now
        let last = points.last?.date ?? .now
        return first...max(last, first.addingTimeInterval(1))
    }

    var body: some View {
        let domain = yDomain
        // 로케일 기본 형식은 한국어에서 "11. 10."처럼 나와 축이 지저분하다 — 언어와 무관하게 M/d로 고정
        let xFormatter = Fmt.date(range == .live ? "HH:mm:ss" : range == .day ? "HH:mm" : "M/d")
        Chart {
            ForEach(bands, id: \.start) { band in
                RectangleMark(xStart: .value("개장", band.start), xEnd: .value("폐장", band.end))
                    .foregroundStyle(Color.primary.opacity(0.06))
            }
            ForEach(events) { event in
                RuleMark(x: .value("일정", event.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .bottom, spacing: 0) {
                        Text(event.icon).font(.system(size: 10))
                    }
            }
            if let selected {
                fomoMarks(selected)
            }
            ForEach(points) { point in
                LineMark(x: .value("시각", point.date), y: .value("가격", point.usd))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(lineColor)
            }
            // 범위 밖 가격의 기록은 찍지 않는다 — 축을 그 가격까지 늘리면 선이 납작해진다
            ForEach(entries.filter { domain.contains($0.usd) }) { entry in
                PointMark(x: .value("기록 시점", entry.date), y: .value("기록가", entry.usd))
                    .symbolSize(entry.isSelected ? 110 : 45)
                    .foregroundStyle(entry.isSelected ? fillColor : Color.secondary)
            }
            if let last = points.last {
                PointMark(x: .value("시각", last.date), y: .value("가격", last.usd))
                    .symbolSize(60)
                    .foregroundStyle(lineColor)
            }
            if let pinned {
                RuleMark(x: .value("선택", pinned.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.primary.opacity(0.35))
                PointMark(x: .value("선택", pinned.date), y: .value("가격", pinned.usd))
                    .symbolSize(90)
                    .foregroundStyle(Color.primary)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xFormatter.string(from: date))
                            .font(.pd(10, .medium, relativeTo: .caption2).monospacedDigit())
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let usd = value.as(Double.self) {
                        Text(formatPrice(usd))
                            .font(.pd(10, .medium, relativeTo: .caption2).monospacedDigit())
                    }
                }
            }
        }
        .chartXSelection(value: $scrubDate)
    }

    /// 선택된 기록: 기록가 수평선 + 기록 시점 이후 기록가~가격 사이를 손익 색으로 채움.
    @ChartContentBuilder
    private func fomoMarks(_ selected: ChartEntryMark) -> some ChartContent {
        ForEach(points.filter { $0.date >= selected.date }) { point in
            AreaMark(x: .value("시각", point.date),
                     yStart: .value("기록가", selected.usd),
                     yEnd: .value("가격", point.usd))
                .interpolationMethod(.monotone)
                .foregroundStyle(fillColor.opacity(0.16))
        }
        RuleMark(y: .value("기록가", selected.usd))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(fillColor.opacity(0.8))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text("\(lang.t("기록가", "Saved")) \(formatPrice(selected.usd))")
                    .font(.pd(10, .semibold, relativeTo: .caption2).monospacedDigit())
                    .foregroundStyle(fillColor)
            }
    }
}
