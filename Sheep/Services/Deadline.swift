import Foundation

/// Runs `op` but returns (throwing `onTimeout`) as soon as `seconds` pass, even if `op` ignores
/// cancellation. A task group can't guarantee that: it waits for every child before returning, so one
/// non-cancellable await (e.g. a shared sign-in request) would stretch the UI's time budget.
func withDeadline<R>(_ seconds: TimeInterval, onTimeout: Error,
                     _ op: @escaping @Sendable () async throws -> R) async throws -> R {
    let race = DeadlineRace<R>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<R, Error>) in
            race.start(cont,
                       work: Task { do { race.finish(.success(try await op())) } catch { race.finish(.failure(error)) } },
                       timer: Task {
                           try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                           race.finish(.failure(onTimeout))
                       })
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

private final class DeadlineRace<R>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<R, Error>?
    private var pending: Result<R, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var done = false

    func start(_ c: CheckedContinuation<R, Error>, work: Task<Void, Never>, timer: Task<Void, Never>) {
        lock.lock()
        tasks = [work, timer]
        if let pending {           // finished (or cancelled) before we got here
            done = true
            lock.unlock()
            work.cancel(); timer.cancel()
            c.resume(with: pending)
            return
        }
        cont = c
        lock.unlock()
    }

    func finish(_ result: Result<R, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        guard let c = cont else {
            if pending == nil { pending = result }
            lock.unlock()
            return
        }
        done = true
        cont = nil
        let toCancel = tasks
        lock.unlock()
        toCancel.forEach { $0.cancel() }
        c.resume(with: result)
    }
}
