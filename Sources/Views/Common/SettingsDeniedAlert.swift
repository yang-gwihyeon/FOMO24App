import FOMOCore
import SwiftUI
import UIKit

/// 시스템 설정에서 꺼진 기능 안내 — 설정 앱 딥링크 버튼 제공.
/// (알림 권한 거부, 라이브 액티비티 꺼짐 등 "앱 표시 ↔ 시스템 상태" 불일치 방지용)
struct SettingsDeniedAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let lang: AppLanguage

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button(lang.t("설정 열기", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(lang.t("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

extension View {
    /// 알림 권한 거부 안내
    func notificationDeniedAlert(isPresented: Binding<Bool>, lang: AppLanguage) -> some View {
        modifier(SettingsDeniedAlert(
            isPresented: isPresented,
            title: lang.t("알림이 꺼져 있어요", "Notifications are off"),
            message: lang.t("설정 > FOMO24 > 알림에서 허용해 주세요.",
                            "Please allow notifications in Settings > FOMO24 > Notifications."),
            lang: lang))
    }

    /// 라이브 액티비티(다이나믹 아일랜드) 꺼짐 안내
    func liveActivityDeniedAlert(isPresented: Binding<Bool>, lang: AppLanguage) -> some View {
        modifier(SettingsDeniedAlert(
            isPresented: isPresented,
            title: lang.t("실시간 활동이 꺼져 있어요", "Live Activities are off"),
            message: lang.t("설정 > FOMO24 > 실시간 활동을 켜면 다이나믹 아일랜드로 시세를 추적할 수 있어요.",
                            "Turn on Live Activities in Settings > FOMO24 to track prices in the Dynamic Island."),
            lang: lang))
    }
}
