import Foundation
import FOMOCore

/// Hyperliquid info 엔드포인트(`metaAndAssetCtxs`, dex="xyz"). API 키 불필요.
/// 주식 선물 시세(PriceService) + FX 선물 환율(FXProvider) 모두 제공.
public struct HyperliquidService: PriceService, FXProvider {
    private let endpoint = URL(string: "https://api.hyperliquid.xyz/info")!
    private let dex = "xyz"

    public init() {}

    public func fetchAssets() async throws -> [StockFuture] {
        let byTicker = try await fetchByTicker()
        return Catalog.tracked.compactMap { entry in
            guard let v = byTicker[entry.ticker] else { return nil }
            return StockFuture(ticker: entry.ticker, usdPrice: v.mark,
                               prevDayPrice: v.prev, volume24h: v.vol)
        }
    }

    public func fetchFXRates() async throws -> [String: Double] {
        let byTicker = try await fetchByTicker()
        var fx: [String: Double] = [:]
        for currency in Currency.allCases {
            guard let t = currency.fxTicker, let v = byTicker[t] else { continue }
            fx[currency.code] = v.mark
        }
        return fx
    }

    // MARK: 공통 요청

    private func fetchByTicker() async throws -> [String: (mark: Double, prev: Double, vol: Double)] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(InfoRequest(type: "metaAndAssetCtxs", dex: dex))
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PriceServiceError.badResponse
        }
        let payload: MetaAndCtxs
        do { payload = try JSONDecoder().decode(MetaAndCtxs.self, from: data) }
        catch { throw PriceServiceError.decoding }

        var map: [String: (mark: Double, prev: Double, vol: Double)] = [:]
        for (meta, ctx) in zip(payload.universe, payload.ctxs) {
            let ticker = Self.shortTicker(meta.name)
            guard let mark = Double(ctx.markPx ?? ""), let prev = Double(ctx.prevDayPx ?? "") else { continue }
            map[ticker] = (mark, prev, Double(ctx.dayNtlVlm ?? "") ?? 0)
        }
        return map
    }

    private static func shortTicker(_ name: String) -> String {
        if let idx = name.firstIndex(of: ":") { return String(name[name.index(after: idx)...]) }
        return name
    }
}

// MARK: - 요청 / 응답 디코딩

private struct InfoRequest: Encodable {
    let type: String
    let dex: String
}

private struct MetaAndCtxs: Decodable {
    let universe: [AssetMeta]
    let ctxs: [AssetCtx]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let meta = try container.decode(Meta.self)
        self.universe = meta.universe
        self.ctxs = try container.decode([AssetCtx].self)
    }
    private struct Meta: Decodable { let universe: [AssetMeta] }
}

private struct AssetMeta: Decodable { let name: String }
private struct AssetCtx: Decodable {
    let markPx: String?
    let prevDayPx: String?
    let dayNtlVlm: String?
}
