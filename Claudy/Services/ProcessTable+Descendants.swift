import Foundation

extension ProcessTable {

    /// Every process below `pid`, closest first. Launchd and the kernel have no tree worth
    /// walking: below them sits the whole machine.
    ///
    /// The `seen` set is what bounds the walk: a malformed table with a loop in it still ends,
    /// each process being visited once.
    func descendants(of pid: pid_t) -> [RunningProcess] {
        guard pid > 1 else { return [] }
        let children = Dictionary(grouping: processes.values, by: \.parent)

        var found: [RunningProcess] = []
        var seen: Set<pid_t> = [pid]
        var level = [pid]

        while !level.isEmpty {
            let next = level
                .flatMap { children[$0] ?? [] }
                .filter { seen.insert($0.pid).inserted }
                .sorted { $0.pid < $1.pid }
            found.append(contentsOf: next)
            level = next.map(\.pid)
        }
        return found
    }
}
