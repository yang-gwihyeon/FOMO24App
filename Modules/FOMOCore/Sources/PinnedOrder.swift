import Foundation

/// 마켓 목록의 "상단 고정" 순서 규칙.
public enum PinnedOrder {
    /// 고정 종목을 맨 앞으로 옮긴다. 나머지 순서(정렬 결과)는 그대로.
    /// 고정 종목이 목록에 없으면(상장 폐지·시세 미수신) 아무것도 바꾸지 않는다.
    public static func apply(_ tickers: [String], pinned: String?) -> [String] {
        guard let pinned, let index = tickers.firstIndex(of: pinned), index > 0 else { return tickers }
        var result = tickers
        result.remove(at: index)
        result.insert(pinned, at: 0)
        return result
    }
}
