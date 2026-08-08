import Foundation

/// 거래소의 오늘 상태(휴장/주말/세션)와 다음 전환 시각을 계산.
/// 휴장일은 2026년 기준(근사). 서머타임/반일장 등 일부 변동은 미반영.
struct MarketSession: Identifiable {

    enum Kind { case pre, regular, post }

    struct Window {
        let kind: Kind
        let open: (h: Int, m: Int)
        let close: (h: Int, m: Int)
    }

    let id: String
    let name: String
    let flag: String
    let timeZoneID: String
    let windows: [Window]                 // open 시각 오름차순
    let holidays: [String: String]         // "MM-dd" → 휴장명 (2026)

    var regular: Window { windows.first { $0.kind == .regular } ?? windows[0] }
    var hasExtended: Bool { windows.contains { $0.kind != .regular } }

    /// 표시 언어에 맞춘 시장 이름. 원격 데이터의 name은 한국어라 영어는 id 매핑으로.
    func localizedName(_ lang: AppLanguage) -> String {
        guard lang != .ko else { return name }
        switch id {
        case "us": return "US (NYSE·NASDAQ)"
        case "kr": return "Korea (KRX·NXT)"
        case "jp": return "Japan (Tokyo)"
        case "uk": return "UK (LSE)"
        default: return name
        }
    }

    /// 시간대별 캘린더 캐시 — Calendar/TimeZone 생성은 비싸서 매 호출 생성 금지.
    /// (status()는 시장시계에서 1초마다, 캘린더 탭에서 날짜×시장만큼 호출됨)
    private static var calendarCache: [String: Calendar] = [:]
    static func calendar(for timeZoneID: String) -> Calendar {
        if let cached = calendarCache[timeZoneID] { return cached }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        calendarCache[timeZoneID] = cal
        return cal
    }

    /// 이 세션의 현지 캘린더 (캐시).
    var marketCalendar: Calendar { Self.calendar(for: timeZoneID) }

    // MARK: 상태 계산

    enum Phase: Equatable {
        case preMarket, regular, afterHours, closed, weekend
        case holiday(String)

        var isTrading: Bool {
            switch self { case .preMarket, .regular, .afterHours: return true; default: return false }
        }
    }

    struct Status {
        let phase: Phase
        let nextChange: Date
    }

    func status(at now: Date) -> Status {
        let cal = marketCalendar

        if let name = holidayName(on: now, cal: cal) {
            return Status(phase: .holiday(name), nextChange: nextRegularOpen(after: now, cal: cal))
        }
        if isWeekend(now, cal: cal) {
            return Status(phase: .weekend, nextChange: nextRegularOpen(after: now, cal: cal))
        }
        // 오늘 세션 내 판정
        for w in windows {
            let open = date(on: now, w.open, cal: cal)
            let close = date(on: now, w.close, cal: cal)
            if now >= open, now < close {
                return Status(phase: phase(for: w.kind), nextChange: close)
            }
            if now < open {
                // 아직 이 세션 전 → 이 세션 시작이 다음 전환
                return Status(phase: .closed, nextChange: open)
            }
        }
        // 오늘 모든 세션 종료
        return Status(phase: .closed, nextChange: nextRegularOpen(after: now, cal: cal))
    }

    private func phase(for kind: Kind) -> Phase {
        switch kind {
        case .pre: return .preMarket
        case .regular: return .regular
        case .post: return .afterHours
        }
    }

    // MARK: 헬퍼

    func holidayName(on date: Date, cal: Calendar) -> String? {
        let c = cal.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return nil }
        return holidays[String(format: "%02d-%02d", m, d)]
    }

    private func isWeekend(_ date: Date, cal: Calendar) -> Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

    private func isTradingDay(_ date: Date, cal: Calendar) -> Bool {
        !isWeekend(date, cal: cal) && holidayName(on: date, cal: cal) == nil
    }

    private func date(on ref: Date, _ hm: (h: Int, m: Int), cal: Calendar) -> Date {
        var comps = cal.dateComponents([.year, .month, .day], from: ref)
        comps.hour = hm.h; comps.minute = hm.m; comps.second = 0
        return cal.date(from: comps) ?? ref
    }

    /// 앞으로의 정규장 개장 시각들 (주말·휴장 건너뜀). 알림 예약용.
    func upcomingRegularOpens(count: Int, from now: Date) -> [Date] {
        let cal = marketCalendar
        var opens: [Date] = []
        // 오늘 개장이 아직 안 지났으면 포함
        if isTradingDay(now, cal: cal) {
            let todayOpen = date(on: now, regular.open, cal: cal)
            if todayOpen > now { opens.append(todayOpen) }
        }
        var day = cal.startOfDay(for: now)
        var guardCount = 0
        while opens.count < count, guardCount < 30 {
            guardCount += 1
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
            if isTradingDay(day, cal: cal) { opens.append(date(on: day, regular.open, cal: cal)) }
        }
        return Array(opens.prefix(count))
    }

    /// 다음 거래일의 정규장 개장 시각 (주말·휴장 건너뜀).
    private func nextRegularOpen(after now: Date, cal: Calendar) -> Date {
        var day = cal.startOfDay(for: now)
        for _ in 0..<15 {
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
            if isTradingDay(day, cal: cal) {
                return date(on: day, regular.open, cal: cal)
            }
        }
        return now
    }

    // MARK: 정의 (4개 거래소, 2026 휴장일)

    /// 현재 사용 중인 세션 목록. 앱 활성화 시 Firestore `config/marketSessions`로 교체됨.
    /// (MarketConfigService.load 참조 — 원격 로드 실패 시 아래 기본값 유지)
    static var all: [MarketSession] = defaults

    static let defaults: [MarketSession] = [
        MarketSession(
            id: "us", name: "미국 (NYSE·NASDAQ)", flag: "🇺🇸", timeZoneID: "America/New_York",
            windows: [
                Window(kind: .pre, open: (4, 0), close: (9, 30)),
                Window(kind: .regular, open: (9, 30), close: (16, 0)),
                Window(kind: .post, open: (16, 0), close: (20, 0))
            ],
            holidays: [
                "01-01": "신정", "01-19": "MLK 데이", "02-16": "워싱턴 탄신일",
                "04-03": "성금요일", "05-25": "메모리얼 데이", "06-19": "준틴스",
                "07-03": "독립기념일(대체)", "09-07": "노동절", "11-26": "추수감사절", "12-25": "성탄절"
            ]),
        MarketSession(
            id: "kr", name: "한국 (KRX·NXT)", flag: "🇰🇷", timeZoneID: "Asia/Seoul",
            windows: [
                // NXT(넥스트레이드) 프리마켓 08:00~08:50, KRX 정규장 09:00~15:30,
                // NXT 애프터마켓 15:30~20:00
                Window(kind: .pre, open: (8, 0), close: (8, 50)),
                Window(kind: .regular, open: (9, 0), close: (15, 30)),
                Window(kind: .post, open: (15, 30), close: (20, 0))
            ],
            holidays: [
                "01-01": "신정", "02-16": "설날", "02-17": "설날", "02-18": "설날",
                "03-02": "삼일절(대체)", "05-05": "어린이날", "05-25": "부처님오신날(대체)",
                "06-06": "현충일", "08-17": "광복절(대체)", "09-24": "추석", "09-25": "추석",
                "09-28": "추석(대체)", "10-05": "개천절(대체)", "10-09": "한글날",
                "12-25": "성탄절", "12-31": "연말 휴장"
            ]),
        MarketSession(
            id: "jp", name: "일본 (도쿄)", flag: "🇯🇵", timeZoneID: "Asia/Tokyo",
            windows: [
                Window(kind: .regular, open: (9, 0), close: (11, 30)),
                Window(kind: .regular, open: (12, 30), close: (15, 0))
            ],
            holidays: [
                "01-01": "정월", "01-02": "연시", "01-03": "연시", "01-12": "성인의 날",
                "02-11": "건국기념일", "02-23": "천황탄생일", "03-20": "춘분",
                "04-29": "쇼와의 날", "05-04": "국민의 휴일", "05-05": "어린이날", "05-06": "대체휴일",
                "07-20": "바다의 날", "08-11": "산의 날", "09-21": "경로의 날", "09-22": "국민의 휴일",
                "09-23": "추분", "10-12": "스포츠의 날", "11-03": "문화의 날", "11-23": "근로감사의 날",
                "12-31": "연말 휴장"
            ]),
        MarketSession(
            id: "uk", name: "영국 (LSE)", flag: "🇬🇧", timeZoneID: "Europe/London",
            windows: [
                Window(kind: .regular, open: (8, 0), close: (16, 30))
            ],
            holidays: [
                "01-01": "신정", "04-03": "성금요일", "04-06": "부활절 월요일",
                "05-04": "5월 뱅크홀리데이", "05-25": "봄 뱅크홀리데이", "08-31": "여름 뱅크홀리데이",
                "12-25": "성탄절", "12-28": "박싱데이(대체)"
            ])
    ]
}

// MARK: Firestore(config/marketSessions) 파싱

extension MarketSession {
    /// Firestore 문서의 sessions 배열 원소 1개 → MarketSession.
    /// windows의 open/close는 "HH:mm" 문자열 (콘솔에서 수정하기 쉽게).
    init?(remote: [String: Any]) {
        guard let id = remote["id"] as? String,
              let name = remote["name"] as? String,
              let flag = remote["flag"] as? String,
              let tz = remote["timeZoneID"] as? String,
              let rawWindows = remote["windows"] as? [[String: Any]]
        else { return nil }
        let windows: [Window] = rawWindows.compactMap { w in
            guard let kind = Kind(remote: w["kind"] as? String ?? ""),
                  let open = Self.hm(w["open"] as? String),
                  let close = Self.hm(w["close"] as? String) else { return nil }
            return Window(kind: kind, open: open, close: close)
        }
        guard windows.contains(where: { $0.kind == .regular }) else { return nil }
        self.init(id: id, name: name, flag: flag, timeZoneID: tz,
                  windows: windows, holidays: remote["holidays"] as? [String: String] ?? [:])
    }

    private static func hm(_ s: String?) -> (h: Int, m: Int)? {
        let parts = (s ?? "").split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}

extension MarketSession.Kind {
    init?(remote: String) {
        switch remote {
        case "pre": self = .pre
        case "regular": self = .regular
        case "post": self = .post
        default: return nil
        }
    }
}
