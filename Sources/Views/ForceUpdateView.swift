import FOMOCore
import SwiftUI

/// 강제 업데이트 화면 — UpdateGate가 켜지면 앱 전체를 대체한다. 닫기 불가.
struct ForceUpdateView: View {
    @Environment(PriceStore.self) private var store
    let storeURL: URL

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        ZStack {
            Theme.page.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                Text(lang.t("업데이트가 필요해요", "Update Required"))
                    .font(.pd(22, .bold, relativeTo: .title2))
                Text(lang.t("새 버전이 나왔어요. 계속 사용하려면\n최신 버전으로 업데이트해주세요.",
                            "A new version is available.\nPlease update to keep using the app."))
                    .font(.pd(14, .regular, relativeTo: .subheadline))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: storeURL) {
                    Text(lang.t("업데이트하러 가기", "Update Now"))
                        .font(.pd(16, .semibold, relativeTo: .headline))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
