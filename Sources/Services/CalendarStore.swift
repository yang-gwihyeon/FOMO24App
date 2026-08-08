import FOMOCore
import MarketKit
import Foundation
import FirebaseFirestore
import Observation
import SwiftUI

/// 이벤트 유형 — 색상·칩 라벨 구분용.
enum CalendarEventType: String {
    case rate       // 금리 (FOMC, 한은 금통위)
    case econ       // 경제지표 (CPI, 고용보고서)
    case earnings   // 실적 발표
    case holiday    // 휴장
    case etc

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .rate: return lang.t("금리", "Rates")
        case .econ: return lang.t("지표", "Data")
        case .earnings: return lang.t("실적", "Earnings")
        case .holiday: return lang.t("휴장", "Closed")
        case .etc: return lang.t("일정", "Event")
        }
    }

    var color: Color {
        switch self {
        case .rate: return Color(hex: 0x8B5CF6)      // 보라
        case .econ: return Color(hex: 0xF59E0B)      // 주황
        case .earnings: return Theme.accent           // 토스 블루
        case .holiday: return Color(hex: 0xF04452)   // 빨강
        case .etc: return .secondary
        }
    }

    var defaultIcon: String {
        switch self {
        case .rate: return "🏛️"
        case .econ: return "📊"
        case .earnings: return "💼"
        case .holiday: return "🌙"
        case .etc: return "📌"
        }
    }
}

/// 투자 캘린더 이벤트 1건. 원격(config/calendar·calendarAuto) 또는 시장 휴장일에서 생성.
struct CalendarEvent: Identifiable {
    let id: String
    let date: Date          // 발생 일시 (KST 입력 기준)
    let hasTime: Bool       // false면 종일 이벤트
    let title: String       // 한국어 (기본)
    let icon: String        // 이모지
    let note: String?
    let type: CalendarEventType
    var userUUID: String? = nil   // 사용자가 직접 추가한 이벤트면 UserCalendarEvent.uuid
    var titleEn: String? = nil    // 영어 제목 (원격 데이터의 titleEn)
    var noteEn: String? = nil

    /// 표시 언어에 맞는 제목/메모. 영어 데이터가 없으면 한국어로 폴백.
    func displayTitle(_ lang: AppLanguage) -> String {
        lang == .ko ? title : (titleEn ?? title)
    }
    func displayNote(_ lang: AppLanguage) -> String? {
        lang == .ko ? note : (noteEn ?? note)
    }
}

/// Firestore `config/calendar`(수동) + `config/calendarAuto`(서버 자동 수집: 실적 등)에서
/// 이벤트를 내려받고, MarketSession의 휴장일을 자동 병합해 캘린더 탭에 공급.
@MainActor
@Observable
final class CalendarStore {
    static let shared = CalendarStore()

    private(set) var remoteEvents: [CalendarEvent] = []

    /// 문서 형식: events = [{date:"yyyy-MM-dd", time:"HH:mm"?, title, icon, note?, type?}]
    /// time은 한국시간(KST) 기준.
    func load() async {
        let db = Firestore.firestore()
        var events: [CalendarEvent] = []
        for doc in ["calendar", "calendarAuto"] {
            guard let snap = try? await db.collection("config").document(doc).getDocument(),
                  let raw = snap.data()?["events"] as? [[String: Any]] else { continue }
            events.append(contentsOf: raw.compactMap(Self.parse))
        }
        if !events.isEmpty {
            let parsed = events
            await MainActor.run { remoteEvents = parsed }
        }
    }

    private static func parse(_ raw: [String: Any]) -> CalendarEvent? {
        guard let dateStr = raw["date"] as? String,
              let title = raw["title"] as? String else { return nil }
        let timeStr = raw["time"] as? String
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = timeStr == nil ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        guard let date = f.date(from: timeStr == nil ? dateStr : "\(dateStr) \(timeStr!)") else { return nil }
        return CalendarEvent(
            id: "\(dateStr)_\(title)",
            date: date,
            hasTime: timeStr != nil,
            title: title,
            icon: raw["icon"] as? String ?? "📌",
            note: raw["note"] as? String,
            type: CalendarEventType(rawValue: raw["type"] as? String ?? "") ?? .etc,
            titleEn: raw["titleEn"] as? String,
            noteEn: raw["noteEn"] as? String
        )
    }

    /// upcoming() 결과 메모이제이션 — 뷰 바디마다 90~180일 × 4시장 휴장일 스캔을
    /// 반복하지 않도록. (@ObservationIgnored: 바디 평가 중 캐시 갱신이 관찰 루프를 안 만들게)
    @ObservationIgnored private var upcomingCache: (key: String, events: [CalendarEvent])?

    /// 원격 이벤트 + 시장 휴장일(자동)을 병합해 오늘부터 daysAhead일까지 날짜순 반환.
    func upcoming(daysAhead: Int = 90, now: Date = .now, lang: AppLanguage = .current) -> [CalendarEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        let cacheKey = "\(today.timeIntervalSince1970)|\(daysAhead)|\(lang.rawValue)|\(remoteEvents.count)"
        if let cached = upcomingCache, cached.key == cacheKey { return cached.events }

        guard let end = cal.date(byAdding: .day, value: daysAhead, to: today) else { return [] }
        var events = remoteEvents.filter { $0.date >= today && $0.date < end }
        events.append(contentsOf: holidayEvents(from: today, to: end, cal: cal, lang: lang))
        let sorted = events.sorted {
            $0.date != $1.date ? $0.date < $1.date : $0.title < $1.title
        }
        upcomingCache = (cacheKey, sorted)
        return sorted
    }

    /// MarketSession 휴장일 → 종일 이벤트. 주말과 겹치는 휴장은 제외(어차피 휴장).
    private func holidayEvents(from start: Date, to end: Date, cal: Calendar, lang: AppLanguage) -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        var day = start
        while day < end {
            let weekday = cal.component(.weekday, from: day)
            if weekday != 1 && weekday != 7 {
                for session in MarketSession.all {
                    if let name = session.holidayName(on: day, cal: session.marketCalendar) {
                        result.append(CalendarEvent(
                            id: "holiday_\(session.id)_\(day.timeIntervalSince1970)",
                            date: day,
                            hasTime: false,
                            title: lang.t("\(session.flag) \(session.name) 휴장",
                                          "\(session.flag) \(session.localizedName(lang)) closed"),
                            icon: "🌙",
                            note: name,
                            type: .holiday
                        ))
                    }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
