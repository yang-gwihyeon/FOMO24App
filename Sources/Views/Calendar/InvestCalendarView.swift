import SwiftUI
import SwiftData

/// 투자 캘린더 탭 — 가로 주간 달력. 좌우 스와이프로 주 이동, 오늘이 속한 주부터 시작.
/// 각 날짜엔 이벤트 유형별 점, 아래엔 해당 주의 이벤트 목록.
/// 소스: Firestore 수동(config/calendar) + 실적 자동 수집(config/calendarAuto)
///       + 휴장일(MarketSession) + 사용자가 직접 추가한 이벤트(SwiftData).
struct InvestCalendarView: View {
    private var store = CalendarStore.shared
    @Environment(PriceStore.self) private var priceStore
    @Environment(\.modelContext) private var context
    @Query(sort: \UserCalendarEvent.date) private var userEvents: [UserCalendarEvent]

    @State private var weekOffset = 0          // 0 = 오늘이 속한 주
    @State private var showingAdd = false
    private let maxWeeks = 26                  // 약 6개월

    private var lang: AppLanguage { priceStore.appLanguage }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekTitle
                TabView(selection: $weekOffset) {
                    ForEach(0..<maxWeeks, id: \.self) { offset in
                        WeekPage(weekStart: weekStart(offset),
                                 events: allEvents,
                                 lang: lang,
                                 onDeleteUser: deleteUserEvent)
                            .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                openAlertBar
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(lang.t("투자 캘린더", "Calendar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if weekOffset != 0 {
                        Button(lang.t("오늘", "Today")) {
                            Haptics.tap()
                            withAnimation(.snappy) { weekOffset = 0 }
                        }
                        .font(.pd(14, .semibold, relativeTo: .subheadline))
                    }
                    Button {
                        Haptics.tap()
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddCalendarEventSheet()
            }
        }
        .task { await store.load() }
    }

    // MARK: 데이터 병합

    /// 원격(수동+자동+휴장일) + 사용자 추가 이벤트.
    private var allEvents: [CalendarEvent] {
        let user = userEvents.map { e in
            CalendarEvent(
                id: "user_\(e.uuid)",
                date: e.date,
                hasTime: e.hasTime,
                title: e.title,
                icon: (CalendarEventType(rawValue: e.typeRaw) ?? .etc).defaultIcon,
                note: e.note.isEmpty ? nil : e.note,
                type: CalendarEventType(rawValue: e.typeRaw) ?? .etc,
                userUUID: e.uuid
            )
        }
        return (store.upcoming(daysAhead: maxWeeks * 7 + 7, lang: lang) + user)
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.title < $1.title }
    }

    private func deleteUserEvent(_ uuid: String) {
        Haptics.tap()
        if let target = userEvents.first(where: { $0.uuid == uuid }) {
            context.delete(target)
        }
    }

    // MARK: 주 계산·헤더

    /// 개장 알림 — 정규장 10분 전 푸시 토글 칩 (더보기에서 이동).
    private var openAlertBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Text(lang.t("개장 알림", "Open Alerts"))
                    .font(.pd(13, .bold, relativeTo: .subheadline))
                Text(lang.t("정규장 10분 전 푸시", "push 10 min before open"))
                    .font(.pd(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Color(hex: 0x888888))
                Spacer()
            }
            .padding(.horizontal, 16)
            HStack(spacing: 8) {
                ForEach(MarketSession.all) { session in
                    OpenAlertChip(session: session, lang: lang)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    /// offset주의 시작(일요일).
    private func weekStart(_ offset: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return cal.date(byAdding: .day, value: offset * 7, to: start) ?? start
    }

    /// "7월 둘째 주" / "July · Week 2" — 주 중간(수요일) 기준이라 월 경계에 걸친 주도 자연스럽게.
    private var weekTitle: some View {
        let cal = Calendar.current
        let mid = cal.date(byAdding: .day, value: 3, to: weekStart(weekOffset)) ?? .now
        let month = cal.component(.month, from: mid)
        let ordinals = ["첫째", "둘째", "셋째", "넷째", "다섯째", "여섯째"]
        let monthNames = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]
        let weekOfMonth = min(max(cal.component(.weekOfMonth, from: mid), 1), 6)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(lang.t("\(month)월 \(ordinals[weekOfMonth - 1]) 주",
                        "\(monthNames[month - 1]) · Week \(weekOfMonth)"))
                .font(.pd(19, .bold, relativeTo: .title3))
                .contentTransition(.numericText())
                .animation(.snappy, value: weekOffset)
            Text(lang.t(String(cal.component(.year, from: mid)) + "년",
                        String(cal.component(.year, from: mid))))
                .font(.pd(12, .medium, relativeTo: .caption))
                .foregroundStyle(.tertiary)
            Spacer()
            if weekOffset > 0 {
                Text(lang.t("\(weekOffset)주 뒤", "+\(weekOffset)w"))
                    .font(.pd(12, .medium, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

// MARK: - 한 주 페이지 (날짜 스트립 + 그 주의 이벤트)

private struct WeekPage: View {
    let weekStart: Date
    let events: [CalendarEvent]
    let lang: AppLanguage
    let onDeleteUser: (String) -> Void

    private var cal: Calendar { Calendar.current }

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekEnd: Date {
        cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    /// 이 주의 이벤트, 날짜별 그룹.
    private var weekDays: [(Date, [CalendarEvent])] {
        let inWeek = events.filter { $0.date >= weekStart && $0.date < weekEnd }
        let dict = Dictionary(grouping: inWeek) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            weekStrip
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            Divider()
            if weekDays.isEmpty {
                emptyWeek
            } else {
                eventList
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                DayCell(day: day, events: eventsOn(day), lang: lang)
            }
        }
    }

    private func eventsOn(_ day: Date) -> [CalendarEvent] {
        events.filter { cal.isDate($0.date, inSameDayAs: day) }
    }

    private var eventList: some View {
        List {
            ForEach(weekDays, id: \.0) { day, dayEvents in
                Section {
                    ForEach(dayEvents) { event in
                        EventLine(event: event, lang: lang)
                            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                            .listRowBackground(Color(uiColor: .systemBackground))
                            .listRowSeparatorTint(Color(uiColor: .separator).opacity(0.4))
                            .swipeActions(edge: .trailing) {
                                if let uuid = event.userUUID {
                                    Button(role: .destructive) {
                                        onDeleteUser(uuid)
                                    } label: {
                                        Label(lang.t("삭제", "Delete"), systemImage: "trash")
                                    }
                                }
                            }
                    }
                } header: {
                    dayHeader(day)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func dayHeader(_ day: Date) -> some View {
        let f = Fmt.date(lang == .ko ? "d일 (E)" : "E, MMM d", locale: lang.locale)
        return HStack(spacing: 6) {
            Text(f.string(from: day))
                .font(.pd(12, .bold, relativeTo: .caption))
                .foregroundStyle(cal.isDateInToday(day) ? Theme.accent : .secondary)
            if cal.isDateInToday(day) {
                Text(lang.t("오늘", "Today"))
                    .font(.pd(10, .bold, relativeTo: .caption2))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Theme.accent, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(Color(uiColor: .systemBackground))
    }

    private var emptyWeek: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(lang.t("이번 주 예정된 이벤트가 없어요", "No events this week"))
                .font(.pd(13, .regular, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            if let next = events.first(where: { $0.date >= weekEnd }) {
                Text(lang.t("다음 이벤트 · \(nextText(next))", "Next · \(nextText(next))"))
                    .font(.pd(12, .medium, relativeTo: .caption))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            Spacer()
        }
    }

    private func nextText(_ event: CalendarEvent) -> String {
        let f = Fmt.date(lang == .ko ? "M/d(E)" : "E M/d", locale: lang.locale)
        return "\(f.string(from: event.date)) \(event.displayTitle(lang))"
    }
}

// MARK: - 날짜 셀 (요일 + 날짜 + 이벤트 점)

private struct DayCell: View {
    let day: Date
    let events: [CalendarEvent]
    let lang: AppLanguage

    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(day) }
    private var isPast: Bool { day < cal.startOfDay(for: .now) }

    var body: some View {
        VStack(spacing: 5) {
            Text(weekdayText)
                .font(.pd(10, .medium, relativeTo: .caption2))
                .foregroundStyle(isToday ? Theme.accent : .secondary)
            Text("\(cal.component(.day, from: day))")
                .font(.pd(16, isToday ? .bold : .semibold, relativeTo: .body).monospacedDigit())
                .foregroundStyle(numberColor)
                .frame(width: 34, height: 34)
                .background(isToday ? Theme.accent : .clear, in: Circle())
            dots
        }
        .frame(maxWidth: .infinity)
    }

    private var weekdayText: String {
        Fmt.date("E", locale: lang.locale).string(from: day)
    }

    private var numberColor: Color {
        if isToday { return .white }
        if isPast { return Color(uiColor: .tertiaryLabel) }
        let wd = cal.component(.weekday, from: day)
        if wd == 1 { return Color(hex: 0xF04452) }
        if wd == 7 { return Theme.accent }
        return .primary
    }

    /// 이벤트 유형별 색 점 (최대 3개).
    private var dots: some View {
        let types = Array(Set(events.map(\.type))).sorted { $0.rawValue < $1.rawValue }.prefix(3)
        return HStack(spacing: 3) {
            if types.isEmpty {
                Circle().fill(.clear).frame(width: 4, height: 4)
            } else {
                ForEach(Array(types), id: \.self) { type in
                    Circle()
                        .fill(isPast ? Color(uiColor: .tertiaryLabel) : type.color)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 4)
    }
}

// MARK: - 이벤트 한 줄

private struct EventLine: View {
    let event: CalendarEvent
    let lang: AppLanguage

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(event.icon)
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(event.displayTitle(lang))
                        .font(.pd(15, .semibold, relativeTo: .body))
                        .lineLimit(1)
                    if event.userUUID != nil {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                if let note = event.displayNote(lang) {
                    Text(note)
                        .font(.pd(12, .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                typeChip
                if event.hasTime {
                    Text(timeText)
                        .font(.pd(12, .medium, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var typeChip: some View {
        Text(event.type.label(lang))
            .font(.pd(10, .bold, relativeTo: .caption2))
            .foregroundStyle(event.type.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(event.type.color.opacity(0.12), in: Capsule())
    }

    private var timeText: String {
        Fmt.date("HH:mm").string(from: event.date)
    }
}

// MARK: - 이벤트 추가 시트

private struct AddCalendarEventSheet: View {
    @Environment(PriceStore.self) private var priceStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var date: Date = .now
    @State private var useTime = false
    @State private var typeRaw = CalendarEventType.etc.rawValue
    @State private var note = ""

    private let types: [CalendarEventType] = [.etc, .earnings, .econ, .rate]
    private var lang: AppLanguage { priceStore.appLanguage }

    var body: some View {
        NavigationStack {
            Form {
                Section(lang.t("제목", "Title")) {
                    TextField(lang.t("예: 삼성전자 실적 발표", "e.g. Samsung earnings"), text: $title)
                }
                Section(lang.t("날짜", "Date")) {
                    DatePicker(lang.t("날짜", "Date"), selection: $date, displayedComponents: .date)
                    Toggle(lang.t("시간 지정", "Set time"), isOn: $useTime)
                    if useTime {
                        DatePicker(lang.t("시간", "Time"), selection: $date, displayedComponents: .hourAndMinute)
                    }
                }
                Section(lang.t("유형", "Type")) {
                    Picker(lang.t("유형", "Type"), selection: $typeRaw) {
                        ForEach(types, id: \.rawValue) { t in
                            Text("\(t.defaultIcon) \(t.label(lang))").tag(t.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(lang.t("메모 (선택)", "Memo (optional)")) {
                    TextField(lang.t("예: 2분기 잠정실적", "e.g. Q2 preliminary results"), text: $note)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle(lang.t("이벤트 추가", "Add Event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("취소", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("저장", "Save")) { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let event = UserCalendarEvent(
            title: title.trimmingCharacters(in: .whitespaces),
            date: date,
            hasTime: useTime,
            typeRaw: typeRaw,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        context.insert(event)
        Haptics.success()
        dismiss()
    }
}


// MARK: - 개장 알림 칩

private struct OpenAlertChip: View {
    let session: MarketSession
    let lang: AppLanguage
    @AppStorage private var on: Bool

    init(session: MarketSession, lang: AppLanguage) {
        self.session = session
        self.lang = lang
        _on = AppStorage(wrappedValue: false, "alertOpen_\(session.id)")
    }

    private var shortLabel: String {
        switch session.id {
        case "us": return lang.t("미국", "US")
        case "kr": return lang.t("한국", "KR")
        case "jp": return lang.t("일본", "JP")
        case "uk": return lang.t("영국", "UK")
        default: return session.id.uppercased()
        }
    }

    var body: some View {
        Button {
            Haptics.tap()
            on.toggle()
            Task { await NotificationManager.shared.rescheduleMarketOpens(enabledIDs: AlertSettings.enabledOpenIDs) }
        } label: {
            HStack(spacing: 4) {
                Text(session.flag)
                Text(shortLabel)
                    .font(.pd(13, .semibold, relativeTo: .subheadline))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(on ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}
