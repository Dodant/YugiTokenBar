#if os(Linux)
import Adwaita
import Foundation

/// Pure row computation so ordering and bar scaling are testable without GTK.
enum LinuxUsageRows {
    /// Oldest first; `today` is shown in the provider table only.
    static func history(_ days: UsageByDay, excluding today: String? = nil) -> [(day: String, total: Int)] {
        days.filter { $0.key != today }.keys.sorted().map { key in
            (day: key, total: days[key]?.values.reduce(0) { $0 + $1.total } ?? 0)
        }
    }
    static func maxTotal(_ rows: [(day: String, total: Int)]) -> Int { rows.map(\.total).max() ?? 0 }
    /// All-zero history never divides by zero.
    static func barTotal(_ rows: [(day: String, total: Int)]) -> Double { Double(max(1, maxTotal(rows))) }
}

@MainActor struct LinuxUsageView: View {
    let snapshot: LinuxSnapshot
    let model: LinuxModel

    var view: Body {
        let rows = snapshot.history.map { LinuxUsageRows.history($0, excluding: snapshot.historyDate) } ?? []
        let barTotal = LinuxUsageRows.barTotal(rows)
        ScrollView {
            VStack(spacing: 10) {
                Text(snapshot.usageHeading()).style("title-3").halign(.start).padding()
                List(Provider.allCases, id: \.rawValue, selection: nil) { provider in
                    HStack(spacing: 10) {
                        Text(provider.linuxDisplayName).hexpand().halign(.start)
                        Text(shortTokens(snapshot.todayDetail[provider.rawValue]?.total ?? 0))
                    }.padding()
                }.boxedList()
                if snapshot.loadingHistory {
                    Text(L("지난 31일을 읽고 있어요…")).padding()
                } else if let error = snapshot.historyError {
                    Text(error).wrap().padding()
                    Button(L("다시 시도")) { model.loadHistory() }.linuxSmokeID("usage-retry-history")
                } else if snapshot.history != nil {
                    if LinuxUsageRows.maxTotal(rows) == 0 {
                        Text(L("지난 31일 기록이 없어요")).padding()
                    } else {
                        List(rows, id: \.day, selection: nil) { row in
                            HStack(spacing: 10) {
                                Text(row.day).halign(.start)
                                Text(shortTokens(row.total)).halign(.start).frame(minWidth: 70)
                                ProgressBar(value: Double(row.total), total: barTotal).hexpand()
                            }.padding().linuxSmokeID("usage-day-\(row.day)")
                        }.boxedList()
                    }
                }
            }.padding()
        }.vexpand()
    }
}
#endif
