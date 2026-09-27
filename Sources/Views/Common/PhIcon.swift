import SwiftUI

/// Phosphor 아이콘 — 라이브러리 대신 로컬 카탈로그(`Assets.xcassets/PhosphorIcons`)의 SVG 7개만 사용.
/// PhosphorSwift 패키지는 아이콘 9,108개를 85MB Assets.car로 통째로 싣는데 앱은 7개만 썼다 (ADR-0008).
/// 사용법: `PhIcon(.broadcastBold, color: .white).frame(width: 15, height: 15)`
struct PhIcon: View {
    enum Name: String {
        case broadcastBold = "broadcast-bold"
        case bellSimpleRingingFill = "bell-simple-ringing-fill"
        case bellSimpleBold = "bell-simple-bold"
        case arrowRightBold = "arrow-right-bold"
        case plusCircleFill = "plus-circle-fill"
        case heartbeatDuotone = "heartbeat-duotone"
        case plusBold = "plus-bold"
    }

    let name: Name
    var color: Color = .primary

    init(_ name: Name, color: Color = .primary) {
        self.name = name
        self.color = color
    }

    var body: some View {
        Image(name.rawValue)
            .renderingMode(.template)   // SVG의 알파(듀오톤 20% 레이어 포함)를 유지한 채 색만 입힘
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
    }
}
