import XCTest
@testable import DungeonCore

final class AdventTests: XCTestCase {
    func date(_ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))!
    }

    func testDoorsOpenOnTheirDayAndStayOpenUntilTheEnd() {
        let store = MemoryStore()
        XCTAssertFalse(Advent.isOn(store, now: date(11, 30)))
        XCTAssertTrue(Advent.isOn(store, now: date(12, 1)))
        XCTAssertTrue(Advent.canOpen(1, store: store, now: date(12, 1)))
        XCTAssertFalse(Advent.canOpen(2, store: store, now: date(12, 1)))
        XCTAssertTrue(Advent.canOpen(2, store: store, now: date(12, 31)), "missed doors stay open")
        XCTAssertEqual(Advent.ready(store, now: date(12, 10)), 10)
    }

    func testOpeningPaysOnce() {
        let store = MemoryStore()
        let wallet = Wallet(store: store)
        let now = date(12, 25)
        let gold = wallet.gold
        guard case .opened = Advent.open(1, store: store, wallet: wallet, now: now) else { return XCTFail() }
        XCTAssertEqual(wallet.gold - gold, 500)
        guard case .already = Advent.open(1, store: store, wallet: wallet, now: now) else { return XCTFail() }
        XCTAssertEqual(wallet.gold - gold, 500)
        _ = Advent.open(25, store: store, wallet: wallet, now: now)
        XCTAssertTrue(GlobalInventory(store: store).items.contains { $0.name == "Starfall Blade" })
        XCTAssertEqual(store.getItem("dd_mystery_coins"), "50")
        _ = Advent.open(13, store: store, wallet: wallet, now: now)
        XCTAssertEqual(GlobalInventory(store: store).items.filter { $0.name == "Root Torch" }.count, 2)
        XCTAssertEqual(Advent.opened(store, now: now), [1, 25, 13])
        guard case .locked = Advent.open(5, store: MemoryStore(), wallet: wallet, now: date(12, 4)) else { return XCTFail() }
    }

    func testEveryDoorHasAPrize() {
        XCTAssertEqual(Advent.days.map(\.day), Array(1...25))
        for p in Advent.days { XCTAssertFalse(Advent.text(p).isEmpty, "door \(p.day)") }
    }
}
