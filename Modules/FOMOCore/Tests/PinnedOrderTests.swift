import Testing
@testable import FOMOCore

struct PinnedOrderTests {
    @Test func 고정_종목은_맨_앞으로() {
        #expect(PinnedOrder.apply(["NVDA", "TSLA", "BTC"], pinned: "BTC") == ["BTC", "NVDA", "TSLA"])
    }

    @Test func 나머지_순서는_유지() {
        #expect(PinnedOrder.apply(["A", "B", "C", "D"], pinned: "C") == ["C", "A", "B", "D"])
    }

    @Test func 고정이_없으면_그대로() {
        #expect(PinnedOrder.apply(["NVDA", "TSLA"], pinned: nil) == ["NVDA", "TSLA"])
    }

    @Test func 목록에_없는_종목을_고정해도_그대로() {
        #expect(PinnedOrder.apply(["NVDA", "TSLA"], pinned: "GONE") == ["NVDA", "TSLA"])
    }

    @Test func 이미_맨_앞이면_그대로() {
        #expect(PinnedOrder.apply(["NVDA", "TSLA"], pinned: "NVDA") == ["NVDA", "TSLA"])
    }
}
