import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 위젯 설정: 종목 선택

struct TickerEntity: AppEntity {
    let id: String               // ticker
    let name: String

    // AppIntents 메타데이터는 컴파일 타임 리터럴만 허용 — 다국어는 String Catalog 필요
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stock"
    static let defaultQuery = TickerQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name) (\(id))")
    }
}

struct TickerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TickerEntity] {
        WK.tickers.filter { identifiers.contains($0.ticker) }
            .map { TickerEntity(id: $0.ticker, name: WK.name($0.ticker)) }
    }

    func suggestedEntities() async throws -> [TickerEntity] {
        WK.tickers.map { TickerEntity(id: $0.ticker, name: WK.name($0.ticker)) }
    }

    func defaultResult() async -> TickerEntity? {
        TickerEntity(id: "NVDA", name: WK.name("NVDA"))
    }
}

struct SelectTickerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Stock"
    static let description = IntentDescription("Pick a stock to show on the widget.")

    @Parameter(title: "Stock")
    var ticker: TickerEntity?
}

// MARK: - 인터랙티브 새로고침 (iOS 17+)

/// 위젯의 새로고침 버튼 — perform 완료 후 WidgetKit이 타임라인을 다시 로드한다.
struct RefreshPricesIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Price"
    static let description = IntentDescription("Reload the latest price.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "PriceWidget")
        return .result()
    }
}

// MARK: - 타임라인

struct PriceEntry: TimelineEntry {
    let date: Date
    let ticker: String
    let name: String
    let price: Double?
    let changePct: Double
}

struct PriceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PriceEntry {
        PriceEntry(date: .now, ticker: "NVDA", name: WK.name("NVDA"), price: 1234.5, changePct: 1.23)
    }

    func snapshot(for configuration: SelectTickerIntent, in context: Context) async -> PriceEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: SelectTickerIntent, in context: Context) async -> Timeline<PriceEntry> {
        let entry = await entry(for: configuration)
        // 위젯 갱신 예산 안에서 15분 주기 요청 (시스템이 재량 조절)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: SelectTickerIntent) async -> PriceEntry {
        let ticker = configuration.ticker?.id ?? "NVDA"
        let name = configuration.ticker?.name ?? WK.name(ticker)
        let quotes = await WidgetFetcher.fetchQuotes()
        let quote = quotes[ticker]
        return PriceEntry(date: .now, ticker: ticker, name: name,
                          price: quote?.price, changePct: quote?.changePct ?? 0)
    }
}

// MARK: - 위젯 뷰

struct PriceWidgetView: View {
    var entry: PriceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Circle()
                    .fill(WK.changeColor(entry.changePct >= 0))
                    .frame(width: 6, height: 6)
            }
            Text(entry.ticker)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer(minLength: 0)
            if let price = entry.price {
                Text(WK.priceText(price))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(WK.pctText(entry.changePct))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WK.changeColor(entry.changePct >= 0))
            } else {
                Text("—")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(intent: RefreshPricesIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }
}

struct PriceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PriceWidget",
                               intent: SelectTickerIntent.self,
                               provider: PriceProvider()) { entry in
            PriceWidgetView(entry: entry)
        }
        .configurationDisplayName(WK.isKorean ? "실시간 주식 시세" : "Live Stock Price")
        .description(WK.isKorean ? "선택한 종목의 24시간 선물 가격을 보여줘요."
                                 : "Shows the 24/7 futures price of your stock.")
        .supportedFamilies([.systemSmall])
    }
}
