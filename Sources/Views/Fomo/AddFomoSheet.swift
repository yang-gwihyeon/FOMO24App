import SwiftUI
import SwiftData

/// FOMO 기록 수동 추가 시트. 종목·가격·날짜/시간·메모 입력.
struct AddFomoSheet: View {
    @Environment(PriceStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var ticker: String = Catalog.tracked.first?.ticker ?? "NVDA"
    @State private var priceText: String = ""
    @State private var savedAt: Date = .now
    @State private var memo: String = ""
    @State private var alertPctText: String = ""
    @State private var showLimitAlert = false

    @Query private var allEntries: [FomoEntry]

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        NavigationStack {
            Form {
                Section(lang.t("종목", "Stock")) {
                    Picker(lang.t("종목", "Stock"), selection: $ticker) {
                        ForEach(Catalog.tracked, id: \.ticker) { entry in
                            Text("\(Catalog.name(for: entry.ticker, language: lang)) (\(entry.ticker))").tag(entry.ticker)
                        }
                    }
                    .onChange(of: ticker) { _, _ in prefillCurrentPrice() }
                }

                Section(lang.t("'샀다 치고' 기준 가격 (USD)", "'What-if' reference price (USD)")) {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    if let usd = store.currentUSDPrice(for: ticker) {
                        Button(lang.t("현재가로 채우기  ($\(String(format: "%.2f", usd)))",
                                      "Use current price  ($\(String(format: "%.2f", usd)))")) {
                            priceText = String(format: "%.2f", usd)
                            Haptics.tap()
                        }
                        .font(.caption)
                    }
                }

                Section(lang.t("기록 시점", "Recorded at")) {
                    DatePicker(lang.t("날짜·시간", "Date & time"), selection: $savedAt, in: ...Date.now)
                }

                Section {
                    HStack {
                        Text("±")
                            .foregroundStyle(.secondary)
                        TextField(lang.t("0 (끔)", "0 (off)"), text: $alertPctText)
                            .keyboardType(.numberPad)
                            .onChange(of: alertPctText) { _, new in
                                // 숫자만, 1% 단위, 최대 두 자리(99%)
                                let filtered = String(new.filter(\.isNumber).prefix(2))
                                if filtered != new { alertPctText = filtered }
                            }
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(lang.t("가격 알림", "Price Alert"))
                } footer: {
                    Text(alertFooterText)
                }

                Section(lang.t("메모 (선택)", "Memo (optional)")) {
                    TextField(lang.t("예: 실적 발표 전에 고민했던 가격", "e.g. the price I hesitated at before earnings"),
                              text: $memo, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .scrollIndicators(.hidden)
            .navigationTitle(lang.t("FOMO 기록 추가", "Add What-if Entry"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("취소", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("저장", "Save")) { save() }
                        .disabled(price == nil)
                }
            }
            .onAppear { if priceText.isEmpty { prefillCurrentPrice() } }
            .alert(lang.t("가격 알림은 최대 \(FomoEntry.maxAlertCount)개", "Up to \(FomoEntry.maxAlertCount) price alerts"), isPresented: $showLimitAlert) {
                Button(lang.t("확인", "OK"), role: .cancel) {}
            } message: {
                Text(lang.t("이미 \(FomoEntry.maxAlertCount)개 기록에 알림이 켜져 있어요. 다른 기록의 알림을 끄거나, 알림 없이 저장해주세요.",
                            "Alerts are already on for \(FomoEntry.maxAlertCount) entries. Turn one off, or save without an alert."))
            }
        }
    }

    private var price: Double? {
        let normalized = priceText.replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private func prefillCurrentPrice() {
        if let usd = store.currentUSDPrice(for: ticker) {
            priceText = String(format: "%.2f", usd)
        }
    }

    private var alertPct: Double { Double(Int(alertPctText) ?? 0) }

    /// 1회성 알림 규칙 안내 — 입력값에 맞춰 예시를 보여줌.
    private var alertFooterText: String {
        let p = Int(alertPct)
        if p > 0 {
            return lang.t("기록 가격에서 ±\(p)%에 도달하면 딱 1번 알림이 와요. 이후엔 알림을 다시 설정해야 또 옵니다. 알림은 최대 \(FomoEntry.maxAlertCount)개까지.",
                          "You'll get exactly one push when the price moves ±\(p)% from your saved price. Re-set the alert to get another. Up to \(FomoEntry.maxAlertCount) alerts.")
        }
        return lang.t("1% 단위로 입력하세요. 비우면 끔. 예: 5 입력 시 ±5% 도달할 때 딱 1번 알림이 와요. 최대 \(FomoEntry.maxAlertCount)개까지.",
                      "Whole % only; leave empty for off. e.g. 5 → one push at ±5%. Up to \(FomoEntry.maxAlertCount) alerts.")
    }

    /// 이미 알림이 켜진 기록 수 (최대 개수 제한용)
    private var activeAlertCount: Int { allEntries.filter { $0.alertPct > 0 }.count }

    private func save() {
        guard let price else { return }
        if alertPct > 0, activeAlertCount >= FomoEntry.maxAlertCount {
            showLimitAlert = true
            return
        }
        let entry = FomoEntry(ticker: ticker, savedPriceUSD: price, savedAt: savedAt, memo: memo, alertPct: alertPct)
        context.insert(entry)
        if alertPct > 0 { Task { await NotificationManager.shared.requestAuthorization() } }
        Haptics.success()
        dismiss()
    }
}
