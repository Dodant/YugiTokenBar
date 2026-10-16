#if os(Linux)
import Foundation

/// 2단계 Linux 진입점: 코어가 Linux 에서 도는지 보여 주는 CLI. 3단계에서 GTK 앱으로 바뀐다
@main
enum LinuxMain {
    static func main() async {
        let db: CardDB
        do { db = try CardDB.bundled() } catch { print("card data: \(error)"); exit(1) }
        let store = StateStore.standard()
        let state = store.load()
        let usage = await TodayUsageReader().read(since: state.claimedDate ?? Game.firstRunSince())
        AppLog.writeAndFlush("linux core smoke: coins=\(state.coins) owned=\(state.distinctOwned)")
        print("YugiTokenBar core on Linux")
        print("save: \(store.url.path)")
        print("log: \(AppLog.logFileURL.path)")
        print("cache: \(TodayUsageReader.defaultHistoryFile.path)")
        print("coins: \(coinText(state.coins))  owned: \(state.distinctOwned)/\(db.cards.count)")
        print("today \(usage.date): \(usage.byProvider.sorted { $0.key < $1.key }.map { "\($0.key)=\(shortTokens($0.value))" }.joined(separator: " "))")
    }
}
#endif
