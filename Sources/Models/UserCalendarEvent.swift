import Foundation
import SwiftData

/// 사용자가 캘린더 탭에서 직접 추가한 이벤트 (기기 로컬 저장).
@Model
final class UserCalendarEvent {
    var title: String
    var date: Date          // 날짜(+시간)
    var hasTime: Bool       // false면 종일
    var typeRaw: String     // CalendarEventType.rawValue
    var note: String
    var uuid: String

    init(title: String, date: Date, hasTime: Bool, typeRaw: String, note: String = "") {
        self.title = title
        self.date = date
        self.hasTime = hasTime
        self.typeRaw = typeRaw
        self.note = note
        self.uuid = UUID().uuidString
    }
}
