import FOMOCore
import MarketKit
import SwiftUI
import SwiftData
import PhosphorSwift

/// 종목 1개 = 여러 거래소 가격을 한 번에 보여주는 플랫 블록.
struct PriceRowView: View {
    let ticker: String
    @Environment(PriceStore.self) private var store
    @Environment(\.modelContext) private var context

    private var lang: AppLanguage { store.appLanguage }
    private var quotesForTicker: [DataSource: StockFuture] { store.sources(for: ticker) }
    private var orderedSources: [DataSource] { DataSource.allCases.filter { quotesForTicker[$0] != nil } }
    private var cheapestPrice: Double? { quotesForTicker.values.map(\.usdPrice).min() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(spacing: 7) {
                ForEach(orderedSources) { source in
                    exchangeLine(source)
                }
            }
            .padding(.leading, 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        // 길게 눌러 실시간 추적 시작/중지 (미지원 기기에서는 메뉴 자체를 숨김)
        .contextMenu {
            if LiveActivityManager.shared.isAvailable {
                let tracking = LiveActivityManager.shared.isTracking(ticker)
                Button {
                    Haptics.tap()
                    if let quote = store.primary(ticker) {
                        LiveActivityManager.shared.toggle(
                            ticker: ticker,
                            name: Catalog.name(for: ticker, language: lang),
                            price: quote.usdPrice,
                            changePct: quote.change24h)
                    }
                } label: {
                    Label(tracking ? lang.t("실시간 추적 중지", "Stop live tracking")
                                   : lang.t("실시간 추적 시작", "Start live tracking"),
                          systemImage: tracking ? "stop.circle" : "waveform")
                }
            }
        }
    }

    // MARK: 종목 헤더

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Catalog.name(for: ticker, language: lang))
                    .font(.pd(16, .semibold, relativeTo: .headline))
                HStack(spacing: 6) {
                    Text(ticker)
                        .font(.pd(11, .medium, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    if let spread = spreadText {
                        Text(spread)
                            .font(.pd(10, .bold, relativeTo: .caption2))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.10), in: Capsule())
                    }
                }
            }
            Spacer()
            trackButton
            quickAddButton
        }
    }

    /// 실시간 추적 버튼 — 지원 기기에서 항상 노출 (발견 가능성).
    /// 라이브 액티비티 미지원 환경(설정에서 끔·아이패드 호환 모드 등)에서는 숨겨서
    /// "눌러도 아무 일 없는 버튼"이 되지 않게 한다.
    @ViewBuilder
    private var trackButton: some View {
        if LiveActivityManager.shared.isAvailable { trackButtonBody }
    }

    private var trackButtonBody: some View {
        let tracking = LiveActivityManager.shared.isTracking(ticker)
        return Button {
            Haptics.tap()
            if let quote = store.primary(ticker) {
                LiveActivityManager.shared.toggle(
                    ticker: ticker,
                    name: Catalog.name(for: ticker, language: lang),
                    price: quote.usdPrice,
                    changePct: quote.change24h)
            }
        } label: {
            Ph.broadcast.bold
                .color(tracking ? .white : Color(uiColor: .tertiaryLabel))
                .frame(width: 15, height: 15)
                .frame(width: 30, height: 30)
                .background(tracking ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear), in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 거래소별 한 줄

    private func exchangeLine(_ source: DataSource) -> some View {
        let sf = quotesForTicker[source]
        let isCheapest = orderedSources.count > 1 && sf?.usdPrice == cheapestPrice
        return HStack(spacing: 8) {
            Text(source.displayName)
                .font(.pd(13, isCheapest ? .semibold : .medium, relativeTo: .subheadline))
                .foregroundStyle(isCheapest ? Theme.accent : .secondary)
            if isCheapest {
                Text(lang.t("최저", "Best"))
                    .font(.pd(9, .bold, relativeTo: .caption2))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
            }
            Spacer()
            if let sf {
                Text(store.formatted(sf.usdPrice))
                    .font(.pd(14, .semibold, relativeTo: .subheadline).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(String(format: "%@%.2f%%", sf.isUp ? "+" : "", sf.change24h))
                    .font(.pd(12, .semibold, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(Theme.changeColor(sf.isUp))
                    .frame(width: 62, alignment: .trailing)
            }
        }
    }

    // MARK: 빠른 추가

    @State private var justAdded = false
    private var quickAddButton: some View {
        Button {
            recordFomo()
        } label: {
            Image(systemName: justAdded ? "checkmark" : "bolt.heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(justAdded ? Theme.up : Color(uiColor: .tertiaryLabel))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recordFomo() {
        guard let usd = store.currentUSDPrice(for: ticker) else { return }
        context.insert(FomoEntry(ticker: ticker, savedPriceUSD: usd))
        Haptics.success()
        store.toast = store.appLanguage.fomoAddedToast
        withAnimation(.snappy) { justAdded = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.snappy) { justAdded = false }
        }
    }

    // MARK: 스프레드

    private var spreadText: String? {
        let prices = quotesForTicker.values.map(\.usdPrice)
        guard let lo = prices.min(), let hi = prices.max(), lo > 0, hi > lo else { return nil }
        return String(format: "\(lang.t("격차", "Spread")) %.2f%%", (hi / lo - 1) * 100)
    }
}
