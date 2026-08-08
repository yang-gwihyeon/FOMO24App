import Foundation

/// 앱 표시 언어. 더보기 탭에서 한국어/영어 선택 (UserDefaults "appLanguage").
/// .ja는 과거 통화 연동 시절의 잔재 — UI에서는 노출하지 않음.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ko, ja

    var id: String { rawValue }

    /// 저장된 언어 — 뷰 밖(알림 등)에서 사용. 최초 설치 기본값은 영어.
    static var current: AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage") {
            return saved == "ko" ? .ko : .en
        }
        return .en
    }

    /// 한/영 한 쌍을 인라인으로 처리하는 헬퍼. (ja는 en으로)
    func t(_ ko: String, _ en: String) -> String {
        self == .ko ? ko : en
    }

    /// 날짜 포매터용 로케일.
    var locale: Locale {
        Locale(identifier: self == .ko ? "ko_KR" : "en_US")
    }

    /// 거래소 기준 안내 문구
    var exchangeNote: String {
        switch self {
        case .en: return "Hyperliquid Perps"
        case .ko: return "Hyperliquid 무기한 선물 기준"
        case .ja: return "Hyperliquid 無期限先物"
        }
    }

    var change24hLabel: String {
        switch self {
        case .en: return "24h change"
        case .ko: return "24h 등락"
        case .ja: return "24h 変動"
        }
    }

    var updatedPrefix: String {
        switch self {
        case .en: return "Updated"
        case .ko: return "갱신"
        case .ja: return "更新"
        }
    }

    var loadingText: String {
        switch self {
        case .en: return "Loading live futures prices…"
        case .ko: return "실시간 선물 가격을 불러오는 중…"
        case .ja: return "リアルタイム先物価格を読み込み中…"
        }
    }

    // MARK: FOMO 트래커

    var thenLabel: String {
        switch self {
        case .en: return "Then"; case .ko: return "그때"; case .ja: return "あの時"
        }
    }

    var nowLabel: String {
        switch self {
        case .en: return "Now"; case .ko: return "지금"; case .ja: return "今"
        }
    }

    /// 올랐을 때(포모) 메시지
    var fomoMessage: String {
        switch self {
        case .en: return "Should've bought it 😭"
        case .ko: return "샀어야 했는데 😭"
        case .ja: return "買っておけば… 😭"
        }
    }

    /// 떨어졌을 때(역포모) 메시지
    var antiFomoMessage: String {
        switch self {
        case .en: return "Glad you didn't 😌"
        case .ko: return "안 사길 잘했다 😌"
        case .ja: return "買わなくて正解 😌"
        }
    }

    var fomoTabTitle: String {
        switch self {
        case .en: return "What-if"; case .ko: return "FOMO"; case .ja: return "FOMO"
        }
    }

    var sortTitle: String {
        switch self {
        case .en: return "Sort by"
        case .ko: return "정렬 기준"
        case .ja: return "並び替え"
        }
    }

    func marketPulse(openCount: Int) -> String {
        switch (self, openCount > 0) {
        case (.ko, true):  return "정규장 \(openCount)곳 개장"
        case (.ko, false): return "정규장 전체 마감 · 24H 거래중"
        case (.ja, true):  return "\(openCount)市場オープン"
        case (.ja, false): return "全市場クローズ · 24H取引中"
        case (_, true):    return "\(openCount) market\(openCount > 1 ? "s" : "") open"
        case (_, false):   return "All markets closed · trading 24H"
        }
    }

    var fomoAddedToast: String {
        switch self {
        case .en: return "Added to What-if"
        case .ko: return "FOMO에 추가됨"
        case .ja: return "FOMOに追加しました"
        }
    }

    var fomoEmptyText: String {
        switch self {
        case .en: return "Record a price you 'almost bought' at.\nWe'll show how much you'd have gained or dodged."
        case .ko: return "'살 뻔했던' 가격을 기록해보세요.\n지금 얼마나 올랐는지(포모) 떨어졌는지(역포모) 보여드려요."
        case .ja: return "「買いそびれた」価格を記録しましょう。\n今どれだけ上がった/下がったかを表示します。"
        }
    }
}
