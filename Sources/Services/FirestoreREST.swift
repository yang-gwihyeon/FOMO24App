import FOMOCore
import Foundation

/// Firestore REST API 최소 클라이언트 — SDK(gRPC 스택 약 50 MB) 대신 URLSession으로 문서를 읽고 쓴다 (ADR-0009).
/// 앱이 쓰는 기능은 문서 단건 get / set(merge) / delete 뿐이라 이 셋만 구현한다.
/// 인증은 SDK와 동일하게 비로그인(API 키만) — 접근 제어는 Firestore 보안 규칙이 담당.
struct FirestoreREST: Sendable {
    enum Error: Swift.Error {
        case notConfigured
        case http(Int)
        case badResponse
    }

    /// `GoogleService-Info.plist`의 프로젝트/키로 구성. 파일이 없거나(더미 CI 빌드) 키가 비면 모든 호출이 `notConfigured`로 실패한다.
    static let shared = FirestoreREST()

    private let baseURL: URL?
    private let apiKey: String?
    private let session: URLSession

    init(projectID: String? = nil, apiKey: String? = nil) {
        var pid = projectID
        var key = apiKey
        if pid == nil || key == nil,
           let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
           let plist = NSDictionary(contentsOf: url) {
            pid = pid ?? plist["PROJECT_ID"] as? String
            key = key ?? plist["API_KEY"] as? String
        }
        self.apiKey = key
        self.baseURL = pid.flatMap {
            URL(string: "https://firestore.googleapis.com/v1/projects/\($0)/databases/(default)/documents")
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData   // 오프라인 폴백은 아래 파일 캐시가 담당
        self.session = URLSession(configuration: config)
    }

    // MARK: - 문서 API

    /// 문서 1건 읽기. 없으면 nil (404). 값은 SDK의 `data()`와 같은 Swift 타입으로 변환된다.
    func getDocument(_ path: String) async throws -> [String: Any]? {
        let (data, status) = try await request("GET", path: path, body: nil, query: [])
        if status == 404 { return nil }
        guard status == 200 else { throw Error.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Error.badResponse }
        return FirestoreJSON.decodeDocument(json)
    }

    /// 문서 쓰기. `merge == true`면 전달한 필드만 갱신(없으면 생성) — SDK `setData(_:merge:)`와 동일.
    /// 값은 Sendable(String·Double·Bool·Date·중첩 컬렉션)로 제한 — MainActor에서 Task로 넘길 때 격리 검사를 통과하기 위해.
    func setDocument(_ path: String, data fields: [String: any Sendable], merge: Bool) async throws {
        let encoded = FirestoreJSON.encodeFields(fields.mapValues { $0 as Any })
        let body = try JSONSerialization.data(withJSONObject: ["fields": encoded])
        let mask = merge ? fields.keys.sorted().map { URLQueryItem(name: "updateMask.fieldPaths", value: $0) } : []
        let (_, status) = try await request("PATCH", path: path, body: body, query: mask)
        guard (200..<300).contains(status) else { throw Error.http(status) }
    }

    /// 문서 삭제. 이미 없어도 성공으로 본다.
    func deleteDocument(_ path: String) async throws {
        let (_, status) = try await request("DELETE", path: path, body: nil, query: [])
        guard (200..<300).contains(status) || status == 404 else { throw Error.http(status) }
    }

    // MARK: - 오프라인 캐시 (config 문서용)

    /// 네트워크 성공 시 캐시에 저장하고, 실패 시 마지막 성공본을 돌려준다.
    /// SDK의 오프라인 퍼시스턴스를 대신하는 최소 구현 — 원격 설정(카탈로그·시장시간·캘린더)에만 사용.
    func getDocumentCached(_ path: String) async -> [String: Any]? {
        let cacheURL = Self.cacheURL(for: path)
        if let doc = try? await getDocument(path) {
            if let data = try? JSONSerialization.data(withJSONObject: doc) {
                try? data.write(to: cacheURL, options: .atomic)   // 캐시 실패는 무시 (다음 성공 때 다시 시도)
            }
            return doc
        }
        guard let data = try? Data(contentsOf: cacheURL),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return doc
    }

    private static func cacheURL(for path: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("firestore-rest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    // MARK: - HTTP

    private func request(_ method: String, path: String, body: Data?, query: [URLQueryItem]) async throws -> (Data, Int) {
        guard let baseURL, let apiKey, !apiKey.isEmpty,
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw Error.notConfigured }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)] + query
        guard let url = components.url else { throw Error.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.badResponse }
        return (data, http.statusCode)
    }
}
