import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

/// Pretendard 폰트 등록 + 앱 전용 타입 스케일.
/// (토스·업비트 등 한국 앱의 시그니처 폰트 — "AI 기본 폰트" 티를 벗는 핵심)
enum AppFont {
    /// 앱 시작 시 1회 등록. 시스템 폰트가 아니라 번들 폰트를 쓰기 위함.
    static func register() {
        let names = ["Pretendard-Regular", "Pretendard-Medium", "Pretendard-SemiBold", "Pretendard-Bold"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "otf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        configureBars()
    }

    /// 내비게이션/탭바 타이틀도 Pretendard로 (전역 일관성).
    private static func configureBars() {
        #if canImport(UIKit)
        guard let large = UIFont(name: "Pretendard-Bold", size: 32),
              let inline = UIFont(name: "Pretendard-SemiBold", size: 17) else { return }
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.largeTitleTextAttributes = [.font: large]
        nav.titleTextAttributes = [.font: inline]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        #endif
    }

    enum Weight {
        case regular, medium, semibold, bold
        var psName: String {
            switch self {
            case .regular:  return "Pretendard-Regular"
            case .medium:   return "Pretendard-Medium"
            case .semibold: return "Pretendard-SemiBold"
            case .bold:     return "Pretendard-Bold"
            }
        }
    }
}

extension Font {
    /// Dynamic Type 대응 커스텀 폰트.
    static func pd(_ size: CGFloat, _ weight: AppFont.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.psName, size: size, relativeTo: style)
    }
}
