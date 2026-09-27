import Foundation
import Testing
@testable import FOMOCore

struct FirestoreJSONTests {
    @Test func 기본_타입_복원() {
        let fields: [String: Any] = [
            "name": ["stringValue": "NVIDIA"],
            "count": ["integerValue": "5"],
            "price": ["doubleValue": 224.71],
            "force": ["booleanValue": true],
        ]
        let d = FirestoreJSON.decodeFields(fields)
        #expect(d["name"] as? String == "NVIDIA")
        #expect(d["count"] as? Int == 5)
        #expect(d["price"] as? Double == 224.71)
        #expect(d["force"] as? Bool == true)
    }

    @Test func 중첩_배열과_맵_복원_카탈로그_형식() {
        let doc: [String: Any] = [
            "name": "projects/x/databases/(default)/documents/config/catalog",
            "fields": [
                "entries": ["arrayValue": ["values": [
                    ["mapValue": ["fields": [
                        "ticker": ["stringValue": "NVDA"],
                        "ko": ["stringValue": "엔비디아"],
                        "order": ["integerValue": "0"],
                    ]]],
                ]]],
            ],
        ]
        let d = FirestoreJSON.decodeDocument(doc)
        let entries = d["entries"] as? [[String: Any]]
        #expect(entries?.count == 1)
        #expect(entries?[0]["ticker"] as? String == "NVDA")
        #expect(entries?[0]["ko"] as? String == "엔비디아")
        #expect(entries?[0]["order"] as? Int == 0)
    }

    @Test func fields_없는_문서는_빈_딕셔너리() {
        #expect(FirestoreJSON.decodeDocument(["name": "x"]).isEmpty)
    }

    @Test func null과_미지원_타입은_키_제거() {
        let d = FirestoreJSON.decodeFields([
            "gone": ["nullValue": NSNull()],
            "geo": ["geoPointValue": ["latitude": 1.0, "longitude": 2.0]],
            "kept": ["stringValue": "ok"],
        ])
        #expect(d.count == 1)
        #expect(d["kept"] as? String == "ok")
    }

    @Test func 타임스탬프_소수점_유무_모두_파싱() {
        let a = FirestoreJSON.parseTimestamp("2026-09-19T12:36:10.123456Z")
        let b = FirestoreJSON.parseTimestamp("2026-09-19T12:36:10Z")
        #expect(a != nil)
        #expect(b != nil)
        #expect(abs((a?.timeIntervalSince1970 ?? 0) - (b?.timeIntervalSince1970 ?? 0)) < 1)
    }

    @Test func 인코딩_타입_태그_매핑() {
        let e = FirestoreJSON.encodeFields([
            "token": "abc",
            "alertPct": 5.0,
            "count": 3,
            "on": true,
            "tags": ["a", "b"],
            "meta": ["k": "v"],
        ])
        #expect((e["token"] as? [String: Any])?["stringValue"] as? String == "abc")
        #expect((e["alertPct"] as? [String: Any])?["doubleValue"] as? Double == 5.0)
        #expect((e["count"] as? [String: Any])?["integerValue"] as? String == "3")
        #expect((e["on"] as? [String: Any])?["booleanValue"] as? Bool == true)
        let tags = (e["tags"] as? [String: Any])?["arrayValue"] as? [String: Any]
        #expect((tags?["values"] as? [[String: Any]])?.count == 2)
        let meta = (e["meta"] as? [String: Any])?["mapValue"] as? [String: Any]
        #expect(((meta?["fields"] as? [String: Any])?["k"] as? [String: Any])?["stringValue"] as? String == "v")
    }

    @Test func 날짜_왕복은_밀리초까지_보존() {
        let date = Date(timeIntervalSince1970: 1_789_816_097.123)
        let encoded = FirestoreJSON.encodeValue(date)
        let text = encoded["timestampValue"] as? String
        #expect(text?.hasSuffix("Z") == true)
        let back = FirestoreJSON.decodeValue(["timestampValue": text ?? ""]) as? Date
        #expect(abs((back?.timeIntervalSince1970 ?? 0) - date.timeIntervalSince1970) < 0.001)
    }

    @Test func 인코딩_후_디코딩_왕복() {
        let original: [String: Any] = ["ticker": "NVDA", "savedPrice": 175.5, "lang": "ko", "n": 2]
        let back = FirestoreJSON.decodeFields(FirestoreJSON.encodeFields(original))
        #expect(back["ticker"] as? String == "NVDA")
        #expect(back["savedPrice"] as? Double == 175.5)
        #expect(back["n"] as? Int == 2)
    }
}
