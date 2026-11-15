import Foundation
import FOMOCore

/// 한 종목의 실시간 가격 흐름. 차트의 "실시간" 탭이 열려 있는 동안만 구독한다.
public protocol LivePriceStream: Sendable {
    /// 스트림을 버리면(취소·화면 이탈) 연결도 닫힌다.
    func prices(ticker: String, isAlwaysOpen: Bool) -> AsyncThrowingStream<Double, Error>
}

/// Hyperliquid WebSocket `activeAssetCtx` 구독 — 목록 화면과 같은 마크 가격(markPx)이 초당 1회쯤 온다.
/// 호가(bbo)·체결(trades)은 더 잦지만 목록의 가격과 값이 달라 화면 간 숫자가 어긋난다.
public struct HyperliquidLiveStream: LivePriceStream {
    private let endpoint = URL(string: "wss://api.hyperliquid.xyz/ws")!
    private let dex = "xyz"

    public init() {}

    public func prices(ticker: String, isAlwaysOpen: Bool) -> AsyncThrowingStream<Double, Error> {
        let coin = isAlwaysOpen ? ticker : "\(dex):\(ticker)"
        let socket = URLSession.shared.webSocketTask(with: endpoint)
        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let body = try JSONEncoder().encode(
                        Subscribe(method: "subscribe", subscription: .init(type: "activeAssetCtx", coin: coin)))
                    guard let text = String(bytes: body, encoding: .utf8) else { throw PriceServiceError.decoding }
                    socket.resume()
                    try await socket.send(.string(text))
                    while !Task.isCancelled {
                        if let price = Self.parse(try await socket.receive()) { continuation.yield(price) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                worker.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    static func parse(_ message: URLSessionWebSocketTask.Message) -> Double? {
        switch message {
        case .string(let text): return parse(Data(text.utf8))
        case .data(let data):   return parse(data)
        @unknown default:       return nil
        }
    }

    /// 구독 확인·다른 채널 메시지는 nil — 가격이 든 메시지만 통과.
    static func parse(_ data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["channel"] as? String == "activeAssetCtx",
              let ctx = (root["data"] as? [String: Any])?["ctx"] as? [String: Any],
              let price = Double(ctx["markPx"] as? String ?? ""), price > 0 else { return nil }
        return price
    }
}

private struct Subscribe: Encodable {
    struct Subscription: Encodable {
        let type: String
        let coin: String
    }
    let method: String
    let subscription: Subscription
}
