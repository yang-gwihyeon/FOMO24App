import SwiftUI
import PhosphorSwift

/// FOMO 기록 한 건. 좌측 컬러 스트라이프(포모=빨강 / 역포모=파랑)로 감정을 한눈에.
/// 획일적 카드가 아니라 시그니처 있는 행.
struct FomoRowView: View {
    let entry: FomoEntry
    /// 벨 버튼 탭 → 알림 % 설정 (FomoView가 입력 다이얼로그 표시)
    var onBellTap: () -> Void = {}
    @Environment(PriceStore.self) private var store

    private var lang: AppLanguage { store.appLanguage }
    private var currentUSD: Double? { store.currentUSDPrice(for: entry.ticker) }
    private var pct: Double? {
        guard let usd = currentUSD else { return nil }
        return entry.returnPct(currentUSD: usd)
    }

    var body: some View {
        let up = (pct ?? 0) >= 0
        let color = Theme.changeColor(up)

        HStack(spacing: 0) {
            // 좌측 시그니처 스트라이프
            Rectangle()
                .fill(pct == nil ? Color(uiColor: .systemGray4) : color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                header(up: up, color: color)
                priceRow
                if !entry.memo.isEmpty {
                    Text(entry.memo)
                        .font(.pd(12, .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func header(up: Bool, color: Color) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Catalog.name(for: entry.ticker, language: lang))
                    .font(.pd(16, .semibold, relativeTo: .headline))
                HStack(spacing: 6) {
                    Text(entry.ticker)
                        .font(.pd(11, .medium, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    bellButton
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let pct {
                    Text(String(format: "%@%.2f%%", up ? "+" : "", pct))
                        .font(.pd(22, .bold, relativeTo: .title2).monospacedDigit())
                        .foregroundStyle(color)
                    Text(up ? lang.fomoMessage : lang.antiFomoMessage)
                        .font(.pd(11, .medium, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").font(.pd(22, .bold, relativeTo: .title2)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 항상 보이는 알림 설정 버튼 — 켜짐: 파란 벨+%, 꺼짐: 회색 벨+"알림".
    private var bellButton: some View {
        let on = entry.alertPct > 0
        return Button(action: onBellTap) {
            HStack(spacing: 3) {
                (on ? Ph.bellSimpleRinging.fill : Ph.bellSimple.bold)
                    .color(on ? Theme.accent : Color.secondary)
                    .frame(width: 11, height: 11)
                Text(on ? "±\(Int(entry.alertPct))%" : lang.t("알림", "Alert"))
                    .font(.pd(10, .semibold, relativeTo: .caption2))
            }
            .foregroundStyle(on ? Theme.accent : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(on ? Theme.accent.opacity(0.12) : Color(uiColor: .tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var priceRow: some View {
        HStack(spacing: 0) {
            labeledPrice(lang.thenLabel, store.formatted(entry.savedPriceUSD), .secondary)
            Ph.arrowRight.bold
                .color(Color(uiColor: .tertiaryLabel))
                .frame(width: 12, height: 12)
                .padding(.horizontal, 12)
            labeledPrice(lang.nowLabel, currentUSD.map { store.formatted($0) } ?? "—", .primary)
            Spacer()
            Text(savedAtText)
                .font(.pd(11, .regular, relativeTo: .caption2))
                .foregroundStyle(.tertiary)
        }
    }

    private func labeledPrice(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.pd(10, .medium, relativeTo: .caption2))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.pd(14, .semibold, relativeTo: .subheadline).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private var savedAtText: String {
        Fmt.date("M/d HH:mm").string(from: entry.savedAt)
    }
}
