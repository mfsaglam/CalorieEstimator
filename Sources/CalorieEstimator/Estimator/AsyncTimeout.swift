enum AsyncTimeout {
    static func run<Value: Sendable>(
        after timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CalorieEstimatorError.modelTimedOut
            }

            guard let first = try await group.next() else {
                throw CalorieEstimatorError.modelTimedOut
            }
            group.cancelAll()
            return first
        }
    }
}
