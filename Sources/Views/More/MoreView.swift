import SwiftUI

/// 더보기 탭 — 설정 · 시장시계 · 용어사전 · 면책고지 · 정보.
struct MoreView: View {
    @Environment(PriceStore.self) private var store

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section(lang.t("언어", "Language")) {
                    Picker(lang.t("언어", "Language"), selection: $store.appLanguage) {
                        Text("English").tag(AppLanguage.en)
                        Text("한국어").tag(AppLanguage.ko)
                    }
                    .pickerStyle(.segmented)
                }

                Section(lang.t("표시 통화", "Display Currency")) {
                    Picker(lang.t("통화", "Currency"), selection: $store.selectedCurrency) {
                        ForEach(Currency.allCases) { c in
                            Text("\(c.flag) \(c.code)").tag(c)
                        }
                    }
                }

                Section {
                    LabeledContent(lang.t("거래소", "Exchanges"), value: "Hyperliquid · Binance · Bitget · Bybit")
                        .font(.footnote)
                } header: {
                    Text(lang.t("데이터 소스", "Data Sources"))
                } footer: {
                    Text(lang.t("4개 거래소를 동시에 비교합니다. 거래소마다 상장 종목이 달라 없는 곳은 표시되지 않아요. 한국 주식(삼성·하이닉스·현대차)은 Hyperliquid에만 있고, 환율은 항상 Hyperliquid 기준.",
                                "Compares 4 exchanges at once. Listings differ by exchange, so unlisted ones are hidden. Korean stocks (Samsung, SK Hynix, Hyundai) trade only on Hyperliquid; FX rates always come from Hyperliquid."))
                }

                Section {
                    Text(lang.t("마켓 탭의 방송 버튼을 누르면 종목 1개를 다이나믹 아일랜드와 잠금화면에서 실시간으로 볼 수 있어요 (다이나믹 아일랜드가 없는 기기는 잠금화면에 표시). 앱 사용 중에는 5초마다, 앱을 꺼도 1분마다 가격이 갱신됩니다. 한 번에 1개 종목만 추적되며, 시스템 정책상 최대 8시간 뒤 자동 종료돼요.",
                                "Tap the broadcast button in the Markets tab to track one stock live in the Dynamic Island and on the Lock Screen (devices without the Dynamic Island show it on the Lock Screen). Prices refresh every 5 seconds while the app is open, and every 1 minute even when it's closed. One stock at a time; iOS ends it automatically after 8 hours."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(lang.t("실시간 추적", "Live Tracking"))
                }

                Section(lang.t("시장", "Market")) {
                    NavigationLink {
                        MarketClockView()
                    } label: {
                        Label(lang.t("시장시계", "Market Clock"), systemImage: "clock")
                    }
                }

                Section(lang.t("정보", "About")) {
                    NavigationLink {
                        DisclaimerView()
                    } label: {
                        Label(lang.t("면책 고지", "Disclaimer"), systemImage: "exclamationmark.shield")
                    }
                    Link(destination: URL(string: lang == .ko
                        ? "https://stock24-fomo.web.app/privacy.html"
                        : "https://stock24-fomo.web.app/privacy-en.html")!) {
                        Label(lang.t("개인정보 처리방침", "Privacy Policy"), systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "mailto:didrnlgus9071@gmail.com")!) {
                        Label(lang.t("문의하기", "Contact Us"), systemImage: "envelope")
                    }
                    LabeledContent(lang.t("버전", "Version"), value: "1.0")
                }

                Section {
                    Text(lang.t("FOMO24는 정보 제공용 시세 추적 앱입니다. 거래를 중개하지 않으며 투자 권유가 아닙니다.",
                                "FOMO24 is an informational price tracker. It does not broker trades and is not investment advice."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle(lang.t("더보기", "More"))
        }
    }
}

/// 면책 고지 — 심사·법적 안전.
struct DisclaimerView: View {
    @Environment(PriceStore.self) private var store
    private var lang: AppLanguage { store.appLanguage }

    private var paragraphs: [String] {
        lang == .ko ? [
            "본 앱은 암호화폐 거래소에서 거래되는 주식 선물·토큰화 주식의 가격 정보를 보여주는 정보 제공 목적의 앱입니다.",
            "본 앱은 어떠한 금융 거래도 중개·실행하지 않으며, 매수·매도 주문 기능을 제공하지 않습니다.",
            "앱에 표시되는 모든 정보는 투자 권유나 투자 자문이 아닙니다. 투자 판단과 그 결과에 대한 책임은 전적으로 이용자 본인에게 있습니다.",
            "가격 데이터는 제3자 거래소 API에서 제공되며, 지연·오류가 있을 수 있고 정확성을 보장하지 않습니다.",
            "‘FOMO’ 기록 기능은 이용자가 입력한 가상의 기준 가격을 저장하는 개인 기록 도구이며, 실제 매수·보유와 무관합니다."
        ] : [
            "This app provides price information for stock futures and tokenized stocks traded on crypto exchanges, for informational purposes only.",
            "It does not broker or execute any financial transactions and provides no buy or sell functions.",
            "Nothing in this app is investment advice or a solicitation. You are solely responsible for your investment decisions and their outcomes.",
            "Price data comes from third-party exchange APIs and may be delayed or inaccurate; accuracy is not guaranteed.",
            "The 'FOMO' feature stores hypothetical reference prices you enter. It is a personal note-taking tool unrelated to actual purchases or holdings."
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(lang.t("면책 고지", "Disclaimer"))
                    .font(.title2.bold())
                ForEach(paragraphs, id: \.self) { para($0) }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(lang.t("면책 고지", "Disclaimer"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func para(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
