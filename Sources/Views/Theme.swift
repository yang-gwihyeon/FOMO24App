import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 앱 전반의 색상/스타일 토큰.
/// 토스·업비트·오늘의집 톤 참고: 깨끗한 회색 배경 + 흰 카드 + 절제된 색 + 거의 평평.
enum Theme {
    // 액센트 (토스 블루)
    static let accent = Color(hex: 0x3182F6)

    // 한국식 등락 색상: 상승=빨강, 하락=파랑
    static let up = Color(hex: 0xF04452)
    static let down = Color(hex: 0x3182F6)

    static func changeColor(_ isUp: Bool) -> Color { isUp ? up : down }

    // 배경/카드 (라이트=회색 위 흰 카드, 다크 자동 대응)
    static var page: Color { Color(uiColor: .systemGroupedBackground) }
    static var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    static let corner: CGFloat = 20

    /// 카드 표준 배경 — 거의 평평한, 아주 옅은 그림자 (토스st)
    static func cardShape(_ radius: CGFloat = corner) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(card)
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 2)
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// 햅틱 피드백 — 네이티브 앱 느낌. UIKit 없을 땐 무시.
enum Haptics {
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
