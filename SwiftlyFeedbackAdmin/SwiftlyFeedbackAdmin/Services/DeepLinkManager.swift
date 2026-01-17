//
//  DeepLinkManager.swift
//  SwiftlyFeedbackAdmin
//
//  Created by Ben Van Aken on 09/01/2026.
//

import SwiftUI

/// Manages deep linking for the Feedback Kit admin app
/// URL scheme: feedbackkit://
@Observable
final class DeepLinkManager {
    static let shared = DeepLinkManager()

    /// The pending navigation destination from a deep link
    var pendingDestination: DeepLinkDestination?

    private init() {}

    /// Handle an incoming URL
    func handleURL(_ url: URL) {
        guard url.scheme == "feedbackkit" else { return }

        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "settings":
            if let firstComponent = pathComponents.first {
                switch firstComponent {
                case "notifications":
                    pendingDestination = .settingsNotifications
                case "push-notifications":
                    pendingDestination = .settingsPushNotifications
                default:
                    pendingDestination = .settings
                }
            } else {
                pendingDestination = .settings
            }

        case "feedback":
            // feedbackkit://feedback/{feedbackId}
            if let feedbackIdString = pathComponents.first,
               let feedbackId = UUID(uuidString: feedbackIdString) {
                pendingDestination = .feedback(id: feedbackId)
            }

        case "project":
            // feedbackkit://project/{projectId}
            if let projectIdString = pathComponents.first,
               let projectId = UUID(uuidString: projectIdString) {
                pendingDestination = .project(id: projectId)
            }

        default:
            break
        }
    }

    /// Clear the pending destination after navigation
    func clearPendingDestination() {
        pendingDestination = nil
    }
}

/// Deep link navigation destinations
enum DeepLinkDestination: Equatable {
    case settings
    case settingsNotifications
    case settingsPushNotifications
    case feedback(id: UUID)
    case project(id: UUID)
}
