import SwiftUI
import SwiftData

// 에누리st 디자인 토큰 — 연회색 배경 + 흰 카드(얇은 보더, 그림자 없음),
// 무채색 텍스트 위계, 이모지 없는 섹션 제목, 틴트 뱃지(radius 4).
private enum CycleUI {
    static var screenBG: Color { Color(uiColor: .systemGroupedBackground) }
    static var cardBG: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var border: Color { Color(uiColor: .separator).opacity(0.35) }
    static let red = Color(hex: 0xF04452)
    static let cardRadius: CGFloat = 16

    static func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(cardBG, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .strokeBorder(border, lineWidth: 1))
    }
}

/// 작은 틴트 뱃지 (에누리 CommonTag 스타일 — radius 4, 11pt).
private struct TintTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.pd(11, .medium, relativeTo: .caption2))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// 순위 뱃지 — Top3는 진하게, 이하는 회색 (에누리 랭킹 패턴).
private struct RankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.pd(12, .bold, relativeTo: .caption).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(rank <= 3 ? Color.black.opacity(0.8) : Color(hex: 0x888888),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - 넥스트 사이클 탭

/// 시장 테마 로테이션 — 사이클 흐름과 다음 후보 랭킹.
/// 데이터: Firestore config/cycles(편집) + cyclesLive(실시간 관심도, 서버 자동 갱신).
struct NextCycleView: View {
    private var store = CycleStore.shared
    @Environment(PriceStore.self) private var priceStore
    @State private var selectedCandidate: CycleCandidate?
    @State private var selectedPast: PastCycle?

    private var lang: AppLanguage { priceStore.appLanguage }

    var body: some View {
        NavigationStack {
            ZStack {
                CycleUI.screenBG.ignoresSafeArea()
                if store.candidates.isEmpty {
                    loadingState
                } else {
                    content
                }
            }
            .navigationTitle(lang.t("넥스트 사이클", "Next Cycle"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await store.load() }
        .sheet(item: $selectedCandidate) { candidate in
            CandidateDetailView(candidate: candidate)
                .environment(priceStore)
        }
        .sheet(item: $selectedPast) { cycle in
            PastCycleDetailView(cycle: cycle, lang: lang)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }

    private var loadingState: some View {
        Group {
            if store.loaded {
                Text(lang.t("사이클 데이터를 불러오지 못했어요", "Couldn't load cycle data"))
                    .font(.pd(13, .regular, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.large)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(lang.t("돈의 흐름", "Money flow"),
                              caption: lang.t("2020년부터", "since 2020"))
                flowStrip
                sectionHeader(lang.t("다음 후보 랭킹", "What could be next"),
                              caption: lang.t("실시간 관심도 반영", "live attention"))
                    .padding(.top, 28)
                rankingCard
                footnote
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: 섹션 헤더 (이모지 없음, bold + 우측 캡션)

    private func sectionHeader(_ title: String, caption: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.pd(19, .bold, relativeTo: .title3))
                .foregroundStyle(.primary)
            Spacer()
            if let caption {
                Text(caption)
                    .font(.pd(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Color(hex: 0x888888))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: 돈의 흐름 — 미니멀 칩 타임라인 (현재 = 검정 채움)

    private var flowStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(store.pastCycles.enumerated()), id: \.element.id) { idx, cycle in
                    let isCurrent = idx == store.pastCycles.count - 1
                    Button {
                        Haptics.tap()
                        selectedPast = cycle
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cycle.period)
                                .font(.pd(10, .medium, relativeTo: .caption2).monospacedDigit())
                                .foregroundStyle(isCurrent ? .white.opacity(0.7) : Color(hex: 0x888888))
                            Text(cycle.displayTitle(lang))
                                .font(.pd(13, .bold, relativeTo: .subheadline))
                                .foregroundStyle(isCurrent ? .white : .primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isCurrent ? Color.black.opacity(0.82) : CycleUI.cardBG,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isCurrent ? .clear : CycleUI.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    if idx < store.pastCycles.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x888888).opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: 후보 랭킹 — 흰 카드 하나에 리더보드 행들

    private var rankingCard: some View {
        CycleUI.card {
            VStack(spacing: 0) {
                ForEach(Array(store.rankedCandidates.enumerated()), id: \.element.id) { idx, candidate in
                    if idx > 0 {
                        Divider().overlay(CycleUI.border).padding(.leading, 52)
                    }
                    Button {
                        Haptics.tap()
                        selectedCandidate = candidate
                    } label: {
                        rankingRow(rank: idx + 1, candidate: candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func rankingRow(rank: Int, candidate: CycleCandidate) -> some View {
        let social = store.socialScores[candidate.id]
        let heat = store.heat(candidate)
        return HStack(spacing: 12) {
            RankBadge(rank: rank)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayTitle(lang))
                    .font(.pd(15, .semibold, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    TintTag(text: candidate.status.label(lang), color: candidate.status.color)
                    if !candidate.relatedTickers.isEmpty {
                        Text(candidate.relatedTickers.joined(separator: " · "))
                            .font(.pd(11, .medium, relativeTo: .caption2))
                            .foregroundStyle(Color(hex: 0x888888))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(heat)")
                    .font(.pd(19, .bold, relativeTo: .title3).monospacedDigit())
                    .foregroundStyle(heat >= 70 ? CycleUI.red : .primary)
                if let social, social.delta != 0 {
                    Text(String(format: "%@%d", social.delta > 0 ? "▲" : "▼", abs(social.delta)))
                        .font(.pd(11, .bold, relativeTo: .caption2).monospacedDigit())
                        .foregroundStyle(Theme.changeColor(social.delta > 0))
                } else {
                    Text(lang.t("관심도", "attn"))
                        .font(.pd(10, .regular, relativeTo: .caption2))
                        .foregroundStyle(Color(hex: 0x888888))
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x888888).opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let live = store.liveUpdatedAt {
                Text(lang.t("관심도 갱신 \(live) · 뉴스·커뮤니티·대중 관심 종합", "Attention updated \(live) · news, community & public interest"))
            }
            Text(lang.t("시장에서 논의되는 테마를 정리한 정보이며 투자 권유가 아닙니다.",
                        "A curated summary of market discussion — not investment advice."))
        }
        .font(.pd(11, .regular, relativeTo: .caption2))
        .foregroundStyle(Color(hex: 0x888888))
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }
}

// MARK: - 지나간 사이클 상세 시트

private struct PastCycleDetailView: View {
    let cycle: PastCycle
    let lang: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cycle.displayTitle(lang))
                    .font(.pd(20, .bold, relativeTo: .title3))
                Text(cycle.period)
                    .font(.pd(13, .medium, relativeTo: .subheadline).monospacedDigit())
                    .foregroundStyle(Color(hex: 0x888888))
                Spacer()
            }
            Text(cycle.displaySummary(lang))
                .font(.pd(14, .regular, relativeTo: .body))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let key = cycle.keyMove {
                TintTag(text: key, color: Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 후보 상세 모달

private struct CandidateDetailView: View {
    let candidate: CycleCandidate
    @Environment(PriceStore.self) private var priceStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var pinnedTickers: Set<String> = []
    @State private var webLink: WebLink?

    private var lang: AppLanguage { priceStore.appLanguage }
    private var social: SocialScore? { CycleStore.shared.socialScores[candidate.id] }

    var body: some View {
        NavigationStack {
            ZStack {
                CycleUI.screenBG.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        hero
                        socialCard
                        thesisCard
                        expertsCard
                        relatedCard
                        eventsCard
                        riskCard
                        sourcesCard
                        Text(lang.t("투자 권유가 아닌 시장 논의 정리입니다.",
                                    "Curated market discussion, not investment advice."))
                            .font(.pd(11, .regular, relativeTo: .caption2))
                            .foregroundStyle(Color(hex: 0x888888))
                            .padding(.horizontal, 4)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(candidate.displayTitle(lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(hex: 0x888888).opacity(0.5))
                    }
                }
            }
            .navigationDestination(item: $webLink) { link in
                WebPageView(url: link.url)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: 히어로 — 순위·상태·종합 관심도

    private var hero: some View {
        CycleUI.card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    RankBadge(rank: candidate.rank)
                    TintTag(text: candidate.status.label(lang), color: candidate.status.color)
                    Spacer()
                }
                Text(candidate.displayTitle(lang))
                    .font(.pd(22, .bold, relativeTo: .title2))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(lang.t("종합 관심도", "Overall heat"))
                        .font(.pd(12, .regular, relativeTo: .caption))
                        .foregroundStyle(Color(hex: 0x888888))
                    Text("\(CycleStore.shared.heat(candidate))")
                        .font(.pd(26, .bold, relativeTo: .title2).monospacedDigit())
                        .foregroundStyle(CycleStore.shared.heat(candidate) >= 70 ? CycleUI.red : .primary)
                    if let social, social.delta != 0 {
                        Text(String(format: "%@%d", social.delta > 0 ? "▲" : "▼", abs(social.delta)))
                            .font(.pd(13, .bold, relativeTo: .caption).monospacedDigit())
                            .foregroundStyle(Theme.changeColor(social.delta > 0))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 카드 공통

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        CycleUI.card {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.pd(15, .bold, relativeTo: .headline))
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 실시간 관심도

    @ViewBuilder
    private var socialCard: some View {
        if let social {
            card(lang.t("실시간 관심도", "Live attention")) {
                sourceBar(lang.t("글로벌 뉴스 볼륨", "Global news volume"), social.news)
                sourceBar(lang.t("헤드라인 언급", "Headline mentions"), social.rss)
                sourceBar(lang.t("대중 관심", "Public interest"), social.wiki)
                sourceBar(lang.t("테크 커뮤니티", "Tech community"), social.hn)
                if social.history.count >= 2 {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(social.history.suffix(14)) { point in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(point.id == social.history.last?.id ? Theme.accent : Theme.accent.opacity(0.25))
                                .frame(height: max(4, CGFloat(point.score) / 100 * 40))
                        }
                    }
                    .frame(height: 40, alignment: .bottom)
                    .padding(.top, 4)
                }
                Text(lang.t("50 = 평소 수준 · 100 = 평소의 2배 · 자동 갱신", "50 = normal · 100 = 2× normal · auto-updated"))
                    .font(.pd(10, .regular, relativeTo: .caption2))
                    .foregroundStyle(Color(hex: 0x888888))
            }
        }
    }

    private func sourceBar(_ label: String, _ value: Int?) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.pd(12, .regular, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                    if let value {
                        Capsule()
                            .fill(value >= 60 ? CycleUI.red : Theme.accent)
                            .frame(width: geo.size.width * CGFloat(min(value, 100)) / 100)
                    }
                }
            }
            .frame(height: 5)
            Text(value.map(String.init) ?? "–")
                .font(.pd(12, .bold, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    // MARK: 논지·근거

    private var thesisCard: some View {
        card(lang.t("왜 주목받나", "Why it's on the radar")) {
            Text(candidate.displayThesis(lang))
                .font(.pd(14, .regular, relativeTo: .body))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(candidate.keyPoints) { point in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.accent)
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    Text(point.display(lang))
                        .font(.pd(13, .regular, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 전문가 뷰

    @ViewBuilder
    private var expertsCard: some View {
        if !candidate.experts.isEmpty {
            card(lang.t("기관·전문가 뷰", "Institutional views")) {
                ForEach(candidate.experts) { expert in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\u{201C}\(expert.display(lang))\u{201D}")
                            .font(.pd(13, .medium, relativeTo: .subheadline))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text(expert.source)
                                .font(.pd(12, .bold, relativeTo: .caption))
                                .foregroundStyle(Theme.accent)
                            if let date = expert.date {
                                Text(date)
                                    .font(.pd(11, .regular, relativeTo: .caption2).monospacedDigit())
                                    .foregroundStyle(Color(hex: 0x888888))
                            }
                            Spacer()
                            if let url = expert.url {
                                Button {
                                    webLink = WebLink(url: url)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0x888888).opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if expert.id != candidate.experts.last?.id {
                            Divider().overlay(CycleUI.border)
                        }
                    }
                }
            }
        }
    }

    // MARK: 관련 종목 — 실시간 시세 + FOMO 박제

    @ViewBuilder
    private var relatedCard: some View {
        if !candidate.relatedTickers.isEmpty || !candidate.relatedOther.isEmpty {
            card(lang.t("관련 종목", "Related names")) {
                ForEach(candidate.relatedTickers, id: \.self) { ticker in
                    tickerRow(ticker)
                    if ticker != candidate.relatedTickers.last {
                        Divider().overlay(CycleUI.border)
                    }
                }
                if !candidate.relatedOther.isEmpty {
                    Text(candidate.relatedOther.joined(separator: " · "))
                        .font(.pd(12, .regular, relativeTo: .caption))
                        .foregroundStyle(Color(hex: 0x888888))
                }
            }
        }
    }

    private func tickerRow(_ ticker: String) -> some View {
        let quote = priceStore.primary(ticker)
        let pinned = pinnedTickers.contains(ticker)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Catalog.name(for: ticker, language: lang))
                    .font(.pd(14, .semibold, relativeTo: .subheadline))
                Text(ticker)
                    .font(.pd(10, .medium, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(Color(hex: 0x888888))
            }
            Spacer()
            if let quote {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceStore.formatted(quote.usdPrice))
                        .font(.pd(14, .semibold, relativeTo: .subheadline).monospacedDigit())
                    Text(String(format: "%@%.2f%%", quote.isUp ? "+" : "", quote.change24h))
                        .font(.pd(11, .semibold, relativeTo: .caption2).monospacedDigit())
                        .foregroundStyle(Theme.changeColor(quote.isUp))
                }
                Button {
                    pinToFomo(ticker, price: quote.usdPrice)
                } label: {
                    Text(pinned ? lang.t("박제됨", "Pinned") : lang.t("FOMO 박제", "Pin to FOMO"))
                        .font(.pd(12, .bold, relativeTo: .caption))
                        .foregroundStyle(pinned ? Theme.up : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(pinned ? Theme.up.opacity(0.12) : Theme.accent,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(pinned)
            } else {
                Text(lang.t("시세 없음", "No quote"))
                    .font(.pd(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Color(hex: 0x888888))
            }
        }
        .padding(.vertical, 2)
    }

    private func pinToFomo(_ ticker: String, price: Double) {
        let memoTitle = candidate.displayTitle(lang)
        let entry = FomoEntry(
            ticker: ticker, savedPriceUSD: price,
            memo: lang.t("사이클 박제 · \(memoTitle)", "Cycle pin · \(memoTitle)"))
        context.insert(entry)
        pinnedTickers.insert(ticker)
        Haptics.success()
    }

    // MARK: 관련 일정

    @ViewBuilder
    private var eventsCard: some View {
        let events = matchedEvents
        if !events.isEmpty {
            card(lang.t("다가오는 관련 일정", "Upcoming events")) {
                ForEach(events.prefix(4)) { event in
                    HStack(spacing: 8) {
                        Text(event.displayTitle(lang))
                            .font(.pd(13, .semibold, relativeTo: .subheadline))
                            .lineLimit(1)
                        Spacer()
                        Text(eventDate(event.date))
                            .font(.pd(12, .medium, relativeTo: .caption).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private var matchedEvents: [CalendarEvent] {
        guard !candidate.relatedTickers.isEmpty else { return [] }
        return CalendarStore.shared.upcoming(daysAhead: 90, lang: lang).filter { event in
            candidate.relatedTickers.contains { event.title.contains($0) || (event.titleEn ?? "").contains($0) }
        }
    }

    private func eventDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = lang.locale
        f.dateFormat = lang == .ko ? "M/d(E)" : "E M/d"
        return f.string(from: date)
    }

    // MARK: 리스크·출처

    @ViewBuilder
    private var riskCard: some View {
        if let risk = candidate.displayRisk(lang) {
            card(lang.t("반대 논리 · 리스크", "Bear case · Risks")) {
                Text(risk)
                    .font(.pd(13, .regular, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var sourcesCard: some View {
        if !candidate.news.isEmpty {
            card(lang.t("출처 · 더 읽기", "Sources")) {
                ForEach(candidate.news) { link in
                    Button {
                        webLink = WebLink(url: link.url)
                    } label: {
                        HStack(spacing: 8) {
                            Text(link.title)
                                .font(.pd(13, .regular, relativeTo: .subheadline))
                                .foregroundStyle(.primary.opacity(0.8))
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if let date = link.date {
                                Text(date)
                                    .font(.pd(11, .regular, relativeTo: .caption2).monospacedDigit())
                                    .foregroundStyle(Color(hex: 0x888888))
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x888888).opacity(0.6))
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
