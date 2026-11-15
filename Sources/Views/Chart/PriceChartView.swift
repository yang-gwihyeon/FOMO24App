import Charts
import FOMOCore
import SwiftUI

/// 차트에 찍는 FOMO 기록 한 건.
struct ChartEntryMark: Identifiable, Hashable {
    let id: String
    let savedAt: Date
    let usd: Double
    let isSelected: Bool
    /// 기록 시점이 차트 기간보다 앞 — 점과 음영을 그리면 "기간 첫날에 산 것"처럼 읽히므로 점선만 긋는다.
    let isBeforeRange: Bool
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
    /// 축 눈금용 — 큰 금액은 소수점 없이 (축이 좁아져 차트가 넓어진다)
    let formatAxis: (Double) -> String
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
            ForEach(entries.filter { domain.contains($0.usd) && !$0.isBeforeRange }) { entry in
                PointMark(x: .value("기록 시점", entry.savedAt), y: .value("기록가", entry.usd))
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
            AxisMarks(values: xTicks) { value in
                AxisValueLabel(anchor: .top) {
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
                        Text(formatAxis(usd))
                            .font(.pd(10, .medium, relativeTo: .caption2).monospacedDigit())
                    }
                }
            }
        }
        .chartXSelection(value: $scrubDate)
    }

    /// 눈금 4개를 기간의 1/8·3/8·5/8·7/8 지점에 둔다 — 자동 눈금은 오른쪽 끝에 걸려 라벨이 잘렸다.
    private var xTicks: [Date] {
        let domain = xDomain
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return [1, 3, 5, 7].map { domain.lowerBound.addingTimeInterval(span * Double($0) / 8) }
    }

    /// 선택된 기록: 기록가 수평선 + (기간 안의 기록이면) 기록 시점 이후 기록가~가격 사이를 손익 색으로 채움.
    @ChartContentBuilder
    private func fomoMarks(_ selected: ChartEntryMark) -> some ChartContent {
        if !selected.isBeforeRange {
            ForEach(points.filter { $0.date >= selected.savedAt }) { point in
                AreaMark(x: .value("시각", point.date),
                         yStart: .value("기록가", selected.usd),
                         yEnd: .value("가격", point.usd))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(fillColor.opacity(0.16))
            }
        }
        // 라벨은 오른쪽 끝, 현재가 반대편에 둔다 — 왼쪽 위에 두면 가격선과 겹쳐 읽히지 않았다.
        // 그래도 선이 기록가를 오르내리면 겹칠 수 있어 배경판을 깔아 글자를 지킨다.
        let lineBelow = (points.last?.usd ?? selected.usd) <= selected.usd
        let prefix = selected.isBeforeRange
            ? "\(Fmt.date("yy.M.d").string(from: selected.savedAt)) \(lang.t("기록가", "saved"))"
            : lang.t("기록가", "Saved")
        RuleMark(y: .value("기록가", selected.usd))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(fillColor.opacity(0.8))
            .annotation(position: lineBelow ? .top : .bottom, alignment: .trailing, spacing: 2) {
                Text("\(prefix) \(formatPrice(selected.usd))")
                    .font(.pd(10, .semibold, relativeTo: .caption2).monospacedDigit())
                    .foregroundStyle(fillColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(uiColor: .systemBackground).opacity(0.85), in: Capsule())
            }
    }
}
