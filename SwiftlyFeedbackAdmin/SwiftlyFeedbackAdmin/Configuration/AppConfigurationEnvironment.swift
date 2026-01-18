//
//  AppConfigurationEnvironment.swift
//  SwiftlyFeedbackAdmin
//
//  SwiftUI Environment key for AppConfiguration injection.
//  This provides a single source of truth for app configuration
//  that flows through the SwiftUI view hierarchy.
//

import SwiftUI

// MARK: - Environment Key

private struct AppConfigurationKey: EnvironmentKey {
    // Use the shared instance as default so all views see the same configuration
    @MainActor static var defaultValue: AppConfiguration {
        AppConfiguration.shared
    }
}

extension EnvironmentValues {
    var appConfiguration: AppConfiguration {
        get { self[AppConfigurationKey.self] }
        set { self[AppConfigurationKey.self] = newValue }
    }
}

// MARK: - View Extension for Convenience

extension View {
    /// Inject AppConfiguration into the environment
    func appConfiguration(_ configuration: AppConfiguration) -> some View {
        environment(\.appConfiguration, configuration)
    }
}
