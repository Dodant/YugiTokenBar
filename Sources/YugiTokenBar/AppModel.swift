import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var game: Game
    /// 마지막 구매 결과 (팩 개봉 창이 보여줌)
    @Published private(set) var opening: [[Pull]] = []
    @Published private(set) var openingID = UUID()
    @Published var showShop = false

    private let store: StateStore
    private var rng = SystemRandomNumberGenerator()
    private var timer: Timer?
    private var refreshing = false

    init(db: CardDB, store: StateStore = .standard()) {
        self.store = store
        self.game = Game(db: db, state: store.load())
    }

    var db: CardDB { game.db }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            let usage = await Task.detached { TodayUsage.read() }.value
            _ = game.claim(today: usage.date, byProvider: usage.byProvider, using: &rng)
            save()
        }
    }

    @discardableResult
    func buy(pack: Int, count: Int) -> Bool {
        let opened = game.buy(pack: pack, count: count, using: &rng)
        guard !opened.isEmpty else { return false }
        opening = opened
        openingID = UUID()
        save()
        return true
    }

    func markSeen() {
        guard game.state.unseenFree > 0 else { return }
        game.state.unseenFree = 0
        save()
    }

    private func save() {
        do { try store.save(game.state) } catch { AppLog.write("state 저장 실패: \(error)") }
    }
}
