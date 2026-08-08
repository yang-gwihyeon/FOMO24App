import SwiftUI

/// 시장시계 — 오늘 기준 거래소별 휴장 여부·정규장 시간·프리/정규/애프터 세션 + 카운트다운.
/// TimelineView로 1초 갱신(경량, 네트워크 없음). 더보기 탭에서 푸시로 진입.
struct MarketClockView: View {
    @Environment(PriceStore.self) private var store
    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        summary(now: now)
                        ForEach(Array(MarketSession.all.enumerated()), id: \.element.id) { idx, session in
                            if idx > 0 { Divider().padding(.leading, 20) }
                            MarketSessionRow(session: session, now: now, lang: lang)
                        }
                        footnote
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle(lang.t("시장시계", "Market Clock"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(now: Date) -> some View {
        let trading = MarketSession.all.filter { $0.status(at: now).phase == .regular }.count
        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
            Text(lang.t("오늘 정규장 열린 곳 ", "Regular sessions open now: "))
                .font(.pd(12, .medium, relativeTo: .caption)).foregroundStyle(.secondary)
            + Text(lang.t("\(trading)곳", "\(trading)"))
                .font(.pd(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.accent)
            + Text(lang.t(" · 선물은 24시간 거래", " · futures trade 24H"))
                .font(.pd(12, .medium, relativeTo: .caption)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var footnote: some View {
        Text(lang.t("※ 2026년 휴장일 기준(근사). 반일장·서머타임 등 일부 변동은 반영되지 않을 수 있어요.",
                    "※ Based on 2026 holidays (approximate). Half-days and DST changes may not be reflected."))
            .font(.pd(11, .regular, relativeTo: .caption2))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
    }
}

private struct MarketSessionRow: View {
    let session: MarketSession
    let now: Date
    let lang: AppLanguage

    private var status: MarketSession.Status { session.status(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            top
            if case .holiday(let name) = status.phase {
                todayLine(icon: "moon.zzz.fill", text: lang.t("오늘 휴장 · \(name)", "Closed today · \(name)"), color: Theme.up)
            } else if status.phase == .weekend {
                todayLine(icon: "moon.zzz.fill", text: lang.t("주말 휴장", "Weekend"), color: .secondary)
            } else if session.hasExtended {
                sessionStrip
            } else {
                todayLine(icon: "clock",
                          text: lang.t("정규장 \(hhmm(session.regular.open))–\(hhmm(session.regular.close)) 현지",
                                       "Regular \(hhmm(session.regular.open))–\(hhmm(session.regular.close)) local"),
                          color: .secondary)
            }
            // 닫혀 있으면 '내 폰 시간' 기준 개장 시각도 표시
            if !status.phase.isTrading {
                todayLine(icon: "iphone",
                          text: lang.t("내 시간 \(localOpenText) 개장", "Opens \(localOpenText) your time"),
                          color: Theme.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var top: some View {
        HStack(spacing: 14) {
            Text(session.flag).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.localizedName(lang))
                    .font(.pd(16, .semibold, relativeTo: .headline))
                Text(countdownText)
                    .font(.pd(12, .medium, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            phaseBadge
        }
    }

    // MARK: 프리/정규/애프터 세션 스트립

    private var sessionStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(session.windows.enumerated()), id: \.offset) { _, w in
                segment(for: w)
            }
        }
    }

    private func segment(for w: MarketSession.Window) -> some View {
        let active = isActive(w)
        return VStack(spacing: 2) {
            Text(kindLabel(w.kind))
                .font(.pd(10, .semibold, relativeTo: .caption2))
            Text("\(hhmm(w.open))–\(hhmm(w.close))")
                .font(.pd(11, .medium, relativeTo: .caption2).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(active ? phaseColor.opacity(0.12) : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(active ? phaseColor : Color.secondary)
    }

    private func todayLine(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.pd(12, .medium, relativeTo: .caption))
        }
        .foregroundStyle(color)
    }

    private var phaseBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(phaseColor).frame(width: 6, height: 6)
            Text(phaseLabel).font(.pd(11, .bold, relativeTo: .caption))
        }
        .foregroundStyle(phaseColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(phaseColor.opacity(0.12), in: Capsule())
    }

    // MARK: 표현 헬퍼

    private func isActive(_ w: MarketSession.Window) -> Bool {
        switch (status.phase, w.kind) {
        case (.preMarket, .pre), (.regular, .regular), (.afterHours, .post): return true
        default: return false
        }
    }

    private var phaseLabel: String {
        switch status.phase {
        case .preMarket:  return lang.t("프리마켓", "Pre-market")
        case .regular:    return lang.t("정규장", "Regular")
        case .afterHours: return lang.t("애프터마켓", "After-hours")
        case .closed:     return lang.t("마감", "Closed")
        case .weekend:    return lang.t("주말", "Weekend")
        case .holiday:    return lang.t("휴장", "Holiday")
        }
    }

    private var phaseColor: Color {
        switch status.phase {
        case .preMarket:  return Color(hex: 0xF59E0B)
        case .regular:    return Color(hex: 0x15C47E)
        case .afterHours: return Color(hex: 0x8B5CF6)
        case .holiday:    return Theme.up
        case .closed, .weekend: return .secondary
        }
    }

    private func kindLabel(_ kind: MarketSession.Kind) -> String {
        switch kind {
        case .pre: return lang.t("프리마켓", "Pre")
        case .regular: return lang.t("정규장", "Regular")
        case .post: return lang.t("애프터마켓", "After")
        }
    }

    private var countdownText: String {
        let secs = max(0, Int(status.nextChange.timeIntervalSince(now)))
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60, s = secs % 60
        let prefix: String
        switch status.phase {
        case .preMarket:  prefix = lang.t("정규장까지", "Regular in")
        case .regular:    prefix = lang.t("마감까지", "Closes in")
        case .afterHours: prefix = lang.t("장 종료까지", "Ends in")
        default:          prefix = lang.t("개장까지", "Opens in")
        }
        if d > 0 { return lang.t("\(prefix) \(d)일 \(h)시간", "\(prefix) \(d)d \(h)h") }
        return String(format: "%@ %02d:%02d:%02d", prefix, h, m, s)
    }

    private func hhmm(_ t: (h: Int, m: Int)) -> String {
        String(format: "%02d:%02d", t.h, t.m)
    }

    /// 다음 개장 시각을 사용자 기기(시스템) 시간대로 표시.
    private var localOpenText: String {
        // timeZone 미지정 → 기기 로컬 기준. 포매터는 캐시 (1초 갱신 뷰라 필수)
        Fmt.date(lang == .ko ? "M/d(E) a h:mm" : "E M/d h:mm a", locale: lang.locale)
            .string(from: status.nextChange)
    }
}
