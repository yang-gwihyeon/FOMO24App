import Foundation
import SwiftData

/// 사용자가 캘린더 탭에서 직접 추가한 이벤트 (기기 로컬 저장).
@Model
public final class UserCalendarEvent {
    public var title: String
    public var date: Date          // 날짜(+시간)
    public var hasTime: Bool       // false면 종일
    public var typeRaw: String     // CalendarEventType.rawValue
    public var note: String
    public var uuid: String

    public init(title: String, date: Date, hasTime: Bool, typeRaw: String, note: String = "") {
        self.title = title
        self.date = date
        self.hasTime = hasTime
        self.typeRaw = typeRaw
        self.note = note
        self.uuid = UUID().uuidString
    }
}
