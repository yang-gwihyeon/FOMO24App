import WidgetKit
import SwiftUI
import ActivityKit

/// 다이나믹 아일랜드 + 잠금화면 실시간 가격.
struct PriceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PriceActivityAttributes.self) { context in
            // 잠금화면 배너
            lockScreenView(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.name)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        Text(context.attributes.ticker)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(WK.priceText(context.state.price))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(WK.pctText(context.state.changePct))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(WK.changeColor(context.state.changePct >= 0))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(WK.isKorean
                         ? "FOMO24 · \(Text(Date(timeIntervalSince1970: context.state.updatedAt), format: .dateTime.hour().minute())) 기준"
                         : "FOMO24 · as of \(Text(Date(timeIntervalSince1970: context.state.updatedAt), format: .dateTime.hour().minute()))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Text(context.attributes.ticker)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            } compactTrailing: {
                Text(WK.pctText(context.state.changePct))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(WK.changeColor(context.state.changePct >= 0))
            } minimal: {
                Circle()
                    .fill(WK.changeColor(context.state.changePct >= 0))
                    .frame(width: 10, height: 10)
            }
            .keylineTint(WK.accent)
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<PriceActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.name)
                    .font(.system(size: 16, weight: .bold))
                Text(context.attributes.ticker)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(WK.priceText(context.state.price))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(WK.pctText(context.state.changePct))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WK.changeColor(context.state.changePct >= 0))
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(uiColor: .systemBackground).opacity(0.85))
    }
}
