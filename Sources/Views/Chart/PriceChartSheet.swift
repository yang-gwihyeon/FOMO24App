import FOMOCore
import MarketKit
import SwiftData
import SwiftUI

/// 종목 차트 시트. 열자마자 세 가지에 답한다:
/// ① 지금 싼 편인가 비싼 편인가 ② 내 "샀다 치고" 기록 이후 어떻게 됐나 ③ 정규장 움직임인가.
struct PriceChartSheet: View {
    let target: ChartTarget
    @Environment(PriceStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var entries: [FomoEntry]

    // 스크린샷 자동화용 초기 기간 지정(-chartRange live) — DEBUG 전용
    #if DEBUG
    @State private var range = ChartRange(rawValue: UserDefaults.standard.string(forKey: "chartRange") ?? "") ?? .week
    #else
    @State private var range: ChartRange = .week
    #endif
    @State private var series: CandleSeries?
    @State private var failed = false
    @State private var scrubDate: Date?
    /// 훑다가 손을 뗀 자리 — chartXSelection은 손을 떼면 nil이 되므로 따로 붙잡아 둔다.
    @State private var pinned: ChartPoint?
    @State private var selectedUUID: String?
    // 실시간 탭: 마지막으로 받은 가격을 1초마다 한 점씩 찍는다 (가격이 안 변해도 선이 흐르도록)
    @State private var livePoints: [ChartPoint] = []
    @State private var liveLatest: Double?
    @State private var liveConnected = false

    init(target: ChartTarget) {
        self.target = target
        let ticker = target.ticker
        _entries = Query(filter: #Predicate<FomoEntry> { $0.ticker == ticker },
                         sort: \.savedAt, order: .reverse)
    }

    private var ticker: String { target.ticker }
    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                headline
                chartArea
                    .frame(height: 230)
                pinStrip
                ChartRangePicker(range: $range, lang: lang)
                entriesSection
                ExchangeCompareView(ticker: ticker)
                upcomingEventRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("chart.sheet")
        .background(Color(uiColor: .systemBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: range) { await load() }
        .task(id: liveActive) { if let series, liveActive { await consumeLive(isAlwaysOpen: series.isAlwaysOpen) } }
        .task(id: liveActive) { if liveActive { await tickLive() } }
        .onChange(of: scrubDate) { _, date in
            guard let date, let point = nearestPoint(to: date), point != pinned else { return }
            pinned = point
        }
        .onChange(of: range) { _, new in
            pinned = nil
            livePoints = []
            liveLatest = nil
            liveConnected = false
            Metrics.event("chart_range", ["ticker": ticker, "range": new.rawValue])
        }
        .onChange(of: scenePhase) { _, phase in
            // 백그라운드에 있던 동안의 빈 구간을 직선으로 잇지 않도록 실시간 창을 새로 깐다
            guard phase == .active, range == .live else { return }
            livePoints = []
            liveLatest = nil
            Task { await load() }
        }
        .onAppear {
            selectedUUID = target.focusUUID ?? entries.first?.uuid
            Metrics.event("chart_open", ["ticker": ticker, "source": target.focusUUID == nil ? "markets" : "fomo"])
        }
    }

    private func load() async {
        failed = false
        if let hit = ChartStore.shared.cached(ticker, range) {
            series = hit
            return
        }
        series = nil
        let loaded = await ChartStore.shared.load(ticker, range)
        guard !Task.isCancelled else { return }
        series = loaded
        failed = loaded == nil
    }

    /// 백그라운드에서는 연결을 끊는다 — 화면에 안 보이는 가격을 받느라 배터리·데이터를 쓰지 않게.
    private var liveActive: Bool { range == .live && series != nil && scenePhase == .active }

    /// 실시간 가격 구독. 끊기면 2초 뒤 다시 붙는다 — 시트가 닫히거나 탭을 바꾸면 task 취소로 끝난다.
    private func consumeLive(isAlwaysOpen: Bool) async {
        let stream = HyperliquidLiveStream()
        // 재연결 간격은 2초에서 30초까지 늘린다 — 거래소 한도가 IP당 분당 새 연결 30개라
        // 오프라인에서 2초마다 두드리면 한도를 다 쓰고, 그러면 복구 후에도 한동안 못 붙는다.
        var delay: UInt64 = 2
        while !Task.isCancelled {
            do {
                for try await price in stream.prices(ticker: ticker, isAlwaysOpen: isAlwaysOpen) {
                    liveLatest = price
                    liveConnected = true
                    delay = 2
                }
            } catch {
                // 연결 실패·끊김 — 아래에서 재연결
            }
            liveConnected = false
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(delay * 2, 30)
        }
    }

    private func tickLive() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let price = liveLatest ?? store.currentUSDPrice(for: ticker) else { continue }
            let now = Date()
            let cutoff = now.addingTimeInterval(-ChartRange.live.duration)
            livePoints.append(ChartPoint(date: now, usd: price))
            if let first = livePoints.first, first.date < cutoff {
                livePoints.removeAll { $0.date < cutoff }
            }
        }
    }
}

// MARK: - 계산

extension PriceChartSheet {
    private var currentUSD: Double? {
        if range == .live, let liveLatest { return liveLatest }
        return store.currentUSDPrice(for: ticker) ?? series?.candles.last?.close
    }

    /// 종가 선. 마지막 점은 진행 중인 봉 대신 5초 폴링 현재가로 덮는다.
    private var points: [ChartPoint] {
        guard let candles = series?.candles, let last = candles.last else { return [] }
        if range == .live { return livePointsWithHistory(candles) }
        var result = candles.dropLast().map { ChartPoint(date: $0.end, usd: $0.close) }
        let now = store.lastUpdated ?? Date()
        let floor = (result.last?.date ?? last.start).addingTimeInterval(1)
        result.append(ChartPoint(date: max(min(last.end, now), floor), usd: currentUSD ?? last.close))
        return result
    }

    /// 실시간: 최근 5분 창. 앞쪽은 1분봉 종가, 구독을 시작한 뒤로는 1초 점.
    private func livePointsWithHistory(_ candles: [Candle]) -> [ChartPoint] {
        let now = livePoints.last?.date ?? Date()
        let cutoff = now.addingTimeInterval(-range.duration)
        let liveStart = livePoints.first?.date ?? now
        var result = candles.map { ChartPoint(date: $0.end, usd: $0.close) }
            .filter { $0.date >= cutoff && $0.date < liveStart }
        result.append(contentsOf: livePoints)
        if livePoints.isEmpty, let currentUSD { result.append(ChartPoint(date: now, usd: currentUSD)) }
        return result
    }

    /// 화면에 그린 점 기준 — 최저·최고가 눈에 보이는 선과 일치하도록.
    private func stats(_ points: [ChartPoint]) -> PriceRangeStats? {
        guard let currentUSD, let first = points.first else { return nil }
        let open = range == .live ? first.usd : (series?.candles.first?.open ?? first.usd)
        return PriceRangeStats(closes: points.map(\.usd), open: open, current: currentUSD)
    }

    private var stats: PriceRangeStats? { stats(points) }

    private var selectedEntry: FomoEntry? {
        entries.first { $0.uuid == selectedUUID }
    }

    private func entryMarks(from start: Date) -> [ChartEntryMark] {
        entries.map {
            ChartEntryMark(id: $0.uuid, date: max($0.savedAt, start), usd: $0.savedPriceUSD,
                           isSelected: $0.uuid == selectedUUID)
        }
    }

    /// 정규장 띠 — 24시간 종목과 긴 기간에서는 그리지 않는다.
    private func bands(_ points: [ChartPoint]) -> [DateInterval] {
        guard let series, !series.isAlwaysOpen, range.showsSessionBands,
              let first = points.first?.date, let last = points.last?.date,
              let session = marketSession else { return [] }
        return session.regularIntervals(from: first, to: last, cal: session.marketCalendar)
    }

    private var marketSession: MarketSession? {
        let id = MarketSession.marketID(forTicker: ticker)
        return MarketSession.all.first { $0.id == id }
    }

    private func matches(_ event: CalendarEvent) -> Bool {
        let ko = Catalog.name(for: ticker, language: .ko)
        let en = Catalog.name(for: ticker, language: .en)
        return event.title.contains(ko) || (event.titleEn ?? event.title).localizedCaseInsensitiveContains(en)
    }

    private func eventMarks(_ points: [ChartPoint]) -> [ChartEventMark] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        return CalendarStore.shared.remoteEvents
            .filter { $0.date >= first && $0.date <= last && matches($0) }
            .map { ChartEventMark(id: $0.id, date: $0.date, icon: $0.icon) }
    }

    private func nearestPoint(to date: Date) -> ChartPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func pctText(_ pct: Double) -> String {
        String(format: "%@%.2f%%", pct >= 0 ? "+" : "", pct)
    }

    private func returnPct(from usd: Double) -> Double? {
        guard let currentUSD, usd > 0 else { return nil }
        return (currentUSD / usd - 1) * 100
    }

    /// 헤드라인 한 줄 — VoiceOver에서는 차트 전체를 이 문장으로 읽는다.
    private func headlineText(_ stats: PriceRangeStats) -> String {
        let label = range.spanLabel(lang)
        switch stats.zone {
        case .high: return lang.t("최근 \(label) 중 고점 근처예요", "Near its \(label) high")
        case .low:  return lang.t("최근 \(label) 중 저점 근처예요", "Near its \(label) low")
        case .mid:  return lang.t("최근 \(label) 범위의 중간쯤이에요", "Mid-range for the past \(label)")
        }
    }

    private func sublineText(_ stats: PriceRangeStats) -> String {
        let pct = Int((stats.position * 100).rounded())
        return lang.t("최저에서 최고까지 \(pct)% 지점 · \(range.spanLabel(lang)) \(pctText(stats.changePct))",
                      "\(pct)% of the way from low to high · \(range.spanLabel(lang)) \(pctText(stats.changePct))")
    }
}

// MARK: - 상단 (종목 · 헤드라인)

extension PriceChartSheet {
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Catalog.name(for: ticker, language: lang))
                    .font(.pd(20, .bold, relativeTo: .title3))
                HStack(spacing: 6) {
                    Text(ticker)
                        .font(.pd(11, .medium, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    if range == .live { ChartLivePill(connected: liveConnected, lang: lang) }
                }
            }
            Spacer()
            Text(currentUSD.map { store.formatted($0) } ?? "—")
                .font(.pd(22, .bold, relativeTo: .title2).monospacedDigit())
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var headline: some View {
        if let stats {
            let color = Theme.changeColor(stats.changePct >= 0)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(headlineText(stats))
                        .font(.pd(17, .bold, relativeTo: .headline))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sublineText(stats))
                        .font(.pd(12, .medium, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                RangePositionBar(stats: stats, color: color, lang: lang, formatPrice: store.formatted)
            }
        } else {
            // 로딩·실패 중에도 아래 내용이 튀지 않게 자리를 잡아 둔다
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 78)
                .opacity(failed ? 0 : 1)
        }
    }
}

// MARK: - 차트 영역

extension PriceChartSheet {
    @ViewBuilder
    private var chartArea: some View {
        let points = points
        if points.count > 1, let stats = stats(points) {
            let selected = selectedEntry
            let fomoUp = (selected.flatMap { returnPct(from: $0.savedPriceUSD) } ?? 0) >= 0
            let bands = bands(points)
            VStack(alignment: .leading, spacing: 4) {
                PriceChartView(
                    points: points,
                    bands: bands,
                    entries: entryMarks(from: points[0].date),
                    events: eventMarks(points),
                    pinned: pinned,
                    lineColor: Theme.changeColor(stats.changePct >= 0),
                    fillColor: Theme.changeColor(fomoUp),
                    range: range,
                    lang: lang,
                    formatPrice: store.formatted,
                    scrubDate: $scrubDate)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(headlineText(stats)). \(sublineText(stats))")
                    .accessibilityIdentifier("chart.plot")
                if !bands.isEmpty, let session = marketSession {
                    Text(lang.t("음영 = \(session.flag) 정규장", "Shaded = \(session.flag) regular session"))
                        .font(.pd(10, .medium, relativeTo: .caption2))
                        .foregroundStyle(.tertiary)
                }
            }
        } else if failed {
            ChartFailedView(lang: lang) { Task { await load() } }
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .overlay { ProgressView() }
        }
    }

    /// 훑은 시점의 "그때 샀다면" + 바로 기록 추가. 높이를 고정해 훑는 동안 화면이 밀리지 않게 한다.
    private var pinStrip: some View {
        HStack(spacing: 10) {
            if let pinned, let pct = returnPct(from: pinned.usd) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Fmt.date(range == .live ? "HH:mm:ss" : "M/d HH:mm").string(from: pinned.date)) · \(store.formatted(pinned.usd))")
                        .font(.pd(11, .medium, relativeTo: .caption2).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("\(lang.t("이때 샀다면 지금", "Bought then, now")) \(pctText(pct))")
                        .font(.pd(14, .bold, relativeTo: .subheadline).monospacedDigit())
                        .foregroundStyle(Theme.changeColor(pct >= 0))
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 4)
                Button { addEntry(at: pinned) } label: {
                    Label(lang.t("기록", "Save"), systemImage: "bolt.heart.fill")
                        .font(.pd(13, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chart.save")
                .accessibilityHint(lang.t("이 시점 가격으로 샀다 치고 기록", "Records a what-if purchase at this point"))
                Button { self.pinned = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lang.t("선택 해제", "Clear selection"))
            } else {
                Image(systemName: "hand.draw")
                    .font(.system(size: 13, weight: .medium))
                Text(lang.t("차트를 훑으면 '그때 샀다면'이 보여요", "Drag across the chart to see \"what if I'd bought then\""))
                    .font(.pd(12, .medium, relativeTo: .caption))
                Spacer()
            }
        }
        .foregroundStyle(.tertiary)
        .frame(minHeight: 40)
    }

    private func addEntry(at point: ChartPoint) {
        let entry = FomoEntry(ticker: ticker, savedPriceUSD: point.usd, savedAt: point.date)
        context.insert(entry)
        Metrics.event("fomo_add", ["ticker": ticker, "source": "chart"])
        Haptics.success()
        withAnimation(.snappy) {
            selectedUUID = entry.uuid
            pinned = nil
        }
    }
}

// MARK: - 내 기록 · 일정

extension PriceChartSheet {
    @ViewBuilder
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.t("내 '샀다 치고' 기록", "My what-if entries"))
                .font(.pd(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            if entries.isEmpty {
                Text(lang.t("아직 이 종목 기록이 없어요. 차트에서 시점을 골라 추가해보세요.",
                            "No entries for this one yet. Pick a point on the chart to add one."))
                    .font(.pd(12, .regular, relativeTo: .caption))
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(entries) { entry in entryChip(entry) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func entryChip(_ entry: FomoEntry) -> some View {
        let selected = entry.uuid == selectedUUID
        let pct = returnPct(from: entry.savedPriceUSD)
        let color = Theme.changeColor((pct ?? 0) >= 0)
        return Button {
            Haptics.tap()
            withAnimation(.snappy) { selectedUUID = selected ? nil : entry.uuid }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Fmt.date("yy.M.d").string(from: entry.savedAt)) · \(store.formatted(entry.savedPriceUSD))")
                    .font(.pd(11, .medium, relativeTo: .caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(pct.map { "\(lang.t("그때 샀다면", "If bought")) \(pctText($0))" } ?? "—")
                    .font(.pd(14, .bold, relativeTo: .subheadline).monospacedDigit())
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? color.opacity(0.12) : Color(uiColor: .tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? color.opacity(0.6) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chart.entry")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 이 종목의 다음 일정(실적 등) — 과거 일정은 차트 x축에, 다가올 일정은 여기에.
    @ViewBuilder
    private var upcomingEventRow: some View {
        if let event = CalendarStore.shared.upcoming(daysAhead: 60, lang: lang).first(where: matches) {
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: .now), to: event.date).day ?? 0
            HStack(spacing: 8) {
                Text(event.icon)
                Text(event.displayTitle(lang))
                    .font(.pd(13, .medium, relativeTo: .subheadline))
                    .lineLimit(1)
                Spacer()
                Text(days <= 0 ? lang.t("오늘", "Today") : "D-\(days)")
                    .font(.pd(12, .bold, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(event.type.color)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}
