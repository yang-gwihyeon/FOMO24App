import FOMOCore
import MarketKit
import SwiftUI

/// 표시 통화 선택 (가로 스크롤 칩).
struct CurrencyPicker: View {
    @Environment(PriceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Currency.allCases) { currency in
                    chip(for: currency, isSelected: store.selectedCurrency == currency)
                        .onTapGesture {
                            Haptics.tap()
                            // withAnimation 금지 — 리스트 전체(모든 가격 텍스트)가
                            // 애니메이션 diff 대상이 되어 탭 직후 프레임이 밀린다.
                            store.selectedCurrency = currency
                        }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(for currency: Currency, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            Text(currency.flag)
            Text(currency.code)
                .font(.pd(13, .semibold, relativeTo: .subheadline))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(Capsule().fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground))))
        .foregroundStyle(isSelected ? .white : .secondary)
    }
}
