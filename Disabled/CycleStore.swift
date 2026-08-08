import Foundation
import FirebaseFirestore
import Observation
import SwiftUI

/// 지나간 사이클 1개 (돈의 흐름 체인).
struct PastCycle: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let titleEn: String?
    let period: String
    let summary: String
    let summaryEn: String?
    let keyMove: String?

    func displayTitle(_ lang: AppLanguage) -> String { lang == .ko ? title : (titleEn ?? title) }
    func displaySummary(_ lang: AppLanguage) -> String { lang == .ko ? summary : (summaryEn ?? summary) }
}

/// 다음 사이클 후보 1개.
struct CycleCandidate: Identifiable {
    enum Status: String {
        case hot, heating, early, cooled

        func label(_ lang: AppLanguage) -> String {
            switch self {
            case .hot: return lang.t("과열", "Hot")
            case .heating: return lang.t("달아오름", "Heating")
            case .early: return lang.t("초기", "Early")
            case .cooled: return lang.t("식음", "Cooled")
            }
        }

        var color: Color {
            switch self {
            case .hot: return Color(hex: 0xF04452)
            case .heating: return Color(hex: 0xF59E0B)
            case .early: return Theme.accent
            case .cooled: return .secondary
            }
        }
    }

    struct NewsLink: Identifiable {
        let id: String
        let title: String
        let url: URL
        let date: String?
    }

    /// 수치 근거 bullet.
    struct KeyPoint: Identifiable {
        let id = UUID()
        let text: String
        let textEn: String?
        func display(_ lang: AppLanguage) -> String { lang == .ko ? text : (textEn ?? text) }
    }

    /// 기관/전문가 의견 (출처 포함).
    struct ExpertView: Identifiable {
        let id = UUID()
        let quote: String
        let quoteEn: String?
        let source: String
        let url: URL?
        let date: String?
        func display(_ lang: AppLanguage) -> String { lang == .ko ? quote : (quoteEn ?? quote) }
    }

    struct TempPoint: Identifiable {
        let id = UUID()
        let date: String
        let temp: Int
    }

    let id: String
    let rank: Int
    let emoji: String
    let title: String
    let titleEn: String?
    let temp: Int               // 기대 온도 0~100
    let status: Status
    let thesis: String
    let thesisEn: String?
    let keyPoints: [KeyPoint]
    let experts: [ExpertView]
    let tempHistory: [TempPoint]
    let relatedTickers: [String]   // 앱 추적 종목 → 시세 연동
    let relatedOther: [String]
    let news: [NewsLink]
    let risk: String?
    let riskEn: String?

    func displayTitle(_ lang: AppLanguage) -> String { lang == .ko ? title : (titleEn ?? title) }
    func displayThesis(_ lang: AppLanguage) -> String { lang == .ko ? thesis : (thesisEn ?? thesis) }
    func displayRisk(_ lang: AppLanguage) -> String? { lang == .ko ? risk : (riskEn ?? risk) }
}

/// 서버(syncSocial)가 매일 계산하는 실시간 관심도 점수.
/// 뉴스(GDELT)·대중(위키 조회수)·테크 커뮤니티(HN)를 각자의 30일 평균과 비교.
/// 50 = 평소 수준, 100 = 평소의 2배 이상.
struct SocialScore {
    struct HistoryPoint: Identifiable {
        let id: String
        let date: String
        let score: Int
    }

    let score: Int
    let delta: Int              // 전일 대비
    let news: Int?              // 뉴스 볼륨 (GDELT)
    let rss: Int?               // 헤드라인 언급 (경제매체 RSS)
    let wiki: Int?              // 대중 관심 (Wikipedia)
    let hn: Int?                // 테크 커뮤니티 (Hacker News)
    let history: [HistoryPoint]
}

/// Firestore `config/cycles`(편집) + `config/cyclesLive`(소셜 점수) + `config/newsTrends`(뉴스 키워드).
@Observable
final class CycleStore {
    static let shared = CycleStore()

    private(set) var pastCycles: [PastCycle] = []
    private(set) var candidates: [CycleCandidate] = []
    private(set) var socialScores: [String: SocialScore] = [:]
    private(set) var updatedAt: String?
    private(set) var liveUpdatedAt: String?
    private(set) var loaded = false

    /// 편집 온도 50% + 실시간 소셜 관심 50% 종합 히트. 소셜 없으면 온도만.
    func heat(_ candidate: CycleCandidate) -> Int {
        guard let social = socialScores[candidate.id] else { return candidate.temp }
        return Int(round(0.5 * Double(candidate.temp) + 0.5 * Double(social.score)))
    }

    /// 종합 히트 내림차순 정렬 — 소셜 점수가 매일 순위를 흔든다.
    var rankedCandidates: [CycleCandidate] {
        candidates.sorted { heat($0) != heat($1) ? heat($0) > heat($1) : $0.rank < $1.rank }
    }

    func load() async {
        let config = Firestore.firestore().collection("config")
        async let cyclesSnap = try? config.document("cycles").getDocument()
        async let liveSnap = try? config.document("cyclesLive").getDocument()
        guard let data = await cyclesSnap?.data() else { return }
        let past = (data["pastCycles"] as? [[String: Any]] ?? []).compactMap(Self.parseCycle)
        let cands = (data["candidates"] as? [[String: Any]] ?? []).compactMap(Self.parseCandidate)
            .sorted { $0.rank < $1.rank }
        let updated = data["updatedAt"] as? String

        var social: [String: SocialScore] = [:]
        var liveUpdated: String?
        if let live = await liveSnap?.data() {
            liveUpdated = (live["updatedAt"] as? String).map { String($0.prefix(10)) }
            for (id, raw) in live["scores"] as? [String: [String: Any]] ?? [:] {
                guard let score = raw["score"] as? Int else { continue }
                let sources = raw["sources"] as? [String: Any] ?? [:]
                let history = (raw["history"] as? [[String: Any]] ?? []).compactMap { h -> SocialScore.HistoryPoint? in
                    guard let d = h["date"] as? String, let s = h["score"] as? Int else { return nil }
                    return SocialScore.HistoryPoint(id: d, date: d, score: s)
                }
                social[id] = SocialScore(
                    score: score,
                    delta: raw["delta"] as? Int ?? 0,
                    news: sources["news"] as? Int,
                    rss: sources["rss"] as? Int,
                    wiki: sources["wiki"] as? Int,
                    hn: sources["hn"] as? Int,
                    history: history
                )
            }
        }

        let socialFinal = social
        let liveFinal = liveUpdated
        await MainActor.run {
            pastCycles = past
            candidates = cands
            socialScores = socialFinal
            updatedAt = updated
            liveUpdatedAt = liveFinal
            loaded = true
        }
    }

    private static func parseCycle(_ raw: [String: Any]) -> PastCycle? {
        guard let id = raw["id"] as? String,
              let title = raw["title"] as? String else { return nil }
        return PastCycle(
            id: id,
            emoji: raw["emoji"] as? String ?? "📈",
            title: title,
            titleEn: raw["titleEn"] as? String,
            period: raw["period"] as? String ?? "",
            summary: raw["summary"] as? String ?? "",
            summaryEn: raw["summaryEn"] as? String,
            keyMove: raw["keyMove"] as? String
        )
    }

    private static func parseCandidate(_ raw: [String: Any]) -> CycleCandidate? {
        guard let id = raw["id"] as? String,
              let title = raw["title"] as? String,
              let thesis = raw["thesis"] as? String else { return nil }
        let news = (raw["news"] as? [[String: Any]] ?? []).compactMap { n -> CycleCandidate.NewsLink? in
            guard let t = n["title"] as? String,
                  let u = n["url"] as? String, let url = URL(string: u) else { return nil }
            return CycleCandidate.NewsLink(id: u, title: t, url: url, date: n["date"] as? String)
        }
        let keyPoints = (raw["keyPoints"] as? [[String: Any]] ?? []).compactMap { k -> CycleCandidate.KeyPoint? in
            guard let t = k["text"] as? String else { return nil }
            return CycleCandidate.KeyPoint(text: t, textEn: k["textEn"] as? String)
        }
        let experts = (raw["experts"] as? [[String: Any]] ?? []).compactMap { e -> CycleCandidate.ExpertView? in
            guard let q = e["quote"] as? String, let s = e["source"] as? String else { return nil }
            return CycleCandidate.ExpertView(
                quote: q, quoteEn: e["quoteEn"] as? String, source: s,
                url: (e["url"] as? String).flatMap(URL.init(string:)), date: e["date"] as? String)
        }
        let tempHistory = (raw["tempHistory"] as? [[String: Any]] ?? []).compactMap { t -> CycleCandidate.TempPoint? in
            guard let d = t["date"] as? String, let v = t["temp"] as? Int else { return nil }
            return CycleCandidate.TempPoint(date: d, temp: v)
        }
        return CycleCandidate(
            id: id,
            rank: raw["rank"] as? Int ?? 99,
            emoji: raw["emoji"] as? String ?? "❓",
            title: title,
            titleEn: raw["titleEn"] as? String,
            temp: raw["temp"] as? Int ?? 50,
            status: CycleCandidate.Status(rawValue: raw["status"] as? String ?? "") ?? .early,
            thesis: thesis,
            thesisEn: raw["thesisEn"] as? String,
            keyPoints: keyPoints,
            experts: experts,
            tempHistory: tempHistory,
            relatedTickers: raw["relatedTickers"] as? [String] ?? [],
            relatedOther: raw["relatedOther"] as? [String] ?? [],
            news: news,
            risk: raw["risk"] as? String,
            riskEn: raw["riskEn"] as? String
        )
    }
}
