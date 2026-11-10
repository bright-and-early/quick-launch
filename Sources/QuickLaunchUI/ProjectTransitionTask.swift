import Foundation

/// Cancellation boundary before any application launch or visibility change.
public enum ProjectTransitionTask {
    public static func start(completion: @escaping @MainActor () -> Void, operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            defer { completion() }
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}
