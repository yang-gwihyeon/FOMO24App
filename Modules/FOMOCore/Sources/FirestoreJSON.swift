import Foundation

/// Firestore REST 문서 형식 ↔ Swift 값 변환 (순수 Foundation).
/// REST는 값을 `{"stringValue": "x"}`, `{"integerValue": "5"}`처럼 타입 태그로 감싸므로
/// SDK의 `DocumentSnapshot.data()`와 같은 `[String: Any]` 모양으로 풀어 기존 파서(`init(remote:)`)를 그대로 쓴다.
/// 네트워크 코드는 앱의 `FirestoreREST`에 있고, 여기는 변환 규칙만 둔다 — 테스트 가능하도록 (ADR-0009).
public enum FirestoreJSON {
    // MARK: - 디코딩 (REST → Swift)

    /// `{"name": ..., "fields": {...}}` 문서 응답 → 필드 딕셔너리. fields가 없으면 빈 딕셔너리.
    public static func decodeDocument(_ document: [String: Any]) -> [String: Any] {
        guard let fields = document["fields"] as? [String: Any] else { return [:] }
        return decodeFields(fields)
    }

    /// 타입 태그가 붙은 필드 맵 → Swift 값. null·미지원 타입은 키를 뺀다 (파서가 기본값으로 처리).
    public static func decodeFields(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, raw) in fields {
            guard let tagged = raw as? [String: Any], let value = decodeValue(tagged) else { continue }
            result[key] = value
        }
        return result
    }

    static func decodeValue(_ tagged: [String: Any]) -> Any? {
        if let s = tagged["stringValue"] as? String { return s }
        if let b = tagged["booleanValue"] as? Bool { return b }
        if let i = tagged["integerValue"] {
            // REST는 64비트 정수를 문자열("5")로 보낸다. 숫자로 올 때도 허용.
            if let s = i as? String, let n = Int(s) { return n }
            if let n = i as? Int { return n }
            if let d = i as? Double { return Int(d) }
        }
        if let d = tagged["doubleValue"] as? Double { return d }
        if let d = tagged["doubleValue"] as? Int { return Double(d) }
        if let t = tagged["timestampValue"] as? String { return parseTimestamp(t) }
        if let arr = tagged["arrayValue"] as? [String: Any] {
            let values = arr["values"] as? [[String: Any]] ?? []
            return values.compactMap(decodeValue)
        }
        if let map = tagged["mapValue"] as? [String: Any] {
            return decodeFields(map["fields"] as? [String: Any] ?? [:])
        }
        if let ref = tagged["referenceValue"] as? String { return ref }
        return nil   // nullValue, bytesValue, geoPointValue — 앱이 쓰지 않음
    }

    // MARK: - 인코딩 (Swift → REST)

    /// Swift 값 딕셔너리 → 타입 태그 필드 맵 (`setData`용).
    public static func encodeFields(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in fields {
            result[key] = encodeValue(value)
        }
        return result
    }

    static func encodeValue(_ value: Any) -> [String: Any] {
        // Bool을 Int보다 먼저, 그리고 정적 타입으로 판별 — NSNumber 브리징으로 1/0이 Bool로 잡히는 것을 막는다
        switch value {
        case let b as Bool where type(of: value) == Bool.self:
            return ["booleanValue": b]
        case let i as Int:
            return ["integerValue": String(i)]
        case let d as Double:
            return ["doubleValue": d]
        case let s as String:
            return ["stringValue": s]
        case let date as Date:
            return ["timestampValue": formatTimestamp(date)]
        case let arr as [Any]:
            return ["arrayValue": ["values": arr.map(encodeValue)]]
        case let map as [String: Any]:
            return ["mapValue": ["fields": encodeFields(map)]]
        default:
            return ["nullValue": NSNull()]
        }
    }

    // MARK: - 타임스탬프 (RFC 3339, UTC)

    /// 포매터는 호출마다 생성 — 원격 설정 로드처럼 드문 경로에서만 쓰이고, 전역 캐시의 동시성 격리를 피한다.
    static func parseTimestamp(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    static func formatTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
