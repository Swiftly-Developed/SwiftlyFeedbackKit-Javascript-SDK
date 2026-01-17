//
//  PushNotificationManager.swift
//  SwiftlyFeedbackAdmin
//

import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private(set) var isRegistered = false
    private(set) var deviceToken: String?
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)

            if granted {
                await registerForRemoteNotifications()
            }

            await updateAuthorizationStatus()
            return granted
        } catch {
            AppLogger.api.error("Failed to request push notification authorization: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() async {
        await updateAuthorizationStatus()
    }

    private func updateAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Registration

    func registerForRemoteNotifications() async {
        #if canImport(UIKit) && !os(watchOS) && !os(macOS)
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #elseif os(macOS)
        await MainActor.run {
            NSApplication.shared.registerForRemoteNotifications()
        }
        #endif
    }

    func didRegisterForRemoteNotifications(withDeviceToken token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        self.isRegistered = true

        AppLogger.api.info("Registered for push notifications with token: \(tokenString.prefix(10))...")

        // Register with server
        Task {
            await registerDeviceWithServer(token: tokenString)
        }
    }

    func didFailToRegisterForRemoteNotifications(withError error: Error) {
        AppLogger.api.error("Failed to register for remote notifications: \(error)")
        self.isRegistered = false
    }

    // MARK: - Server Registration

    private func registerDeviceWithServer(token: String) async {
        do {
            let request = RegisterDeviceRequest(
                token: token,
                platform: currentPlatform,
                appVersion: appVersion,
                osVersion: osVersion
            )

            let _: DeviceTokenResponse = try await AdminAPIClient.shared.post(
                path: "devices/register",
                body: request,
                requiresAuth: true
            )

            AppLogger.api.info("Successfully registered device with server")
        } catch {
            AppLogger.api.error("Failed to register device with server: \(error)")
        }
    }

    func unregisterDevice() async {
        guard let token = deviceToken else { return }

        do {
            // URL encode the token for the path
            let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
            try await AdminAPIClient.shared.delete(
                path: "devices/token/\(encodedToken)",
                requiresAuth: true
            )

            self.deviceToken = nil
            self.isRegistered = false

            AppLogger.api.info("Successfully unregistered device from server")
        } catch {
            AppLogger.api.error("Failed to unregister device: \(error)")
        }
    }

    // MARK: - Notification Handling

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo

        // Extract action URL for deep linking
        if let actionUrlString = userInfo["action_url"] as? String,
           let url = URL(string: actionUrlString) {
            DeepLinkManager.shared.handleURL(url)
        }
    }

    // MARK: - Helpers

    private var currentPlatform: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "unknown"
        #endif
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private var osVersion: String {
        #if os(iOS)
        return UIDevice.current.systemVersion
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        return "unknown"
        #endif
    }
}

// MARK: - API Models

nonisolated
struct RegisterDeviceRequest: Encodable, Sendable {
    let token: String
    let platform: String
    let appVersion: String?
    let osVersion: String?
}

nonisolated
struct DeviceTokenResponse: Decodable, Sendable {
    let id: UUID
    let platform: String
    let appVersion: String?
    let isActive: Bool
    let lastUsedAt: Date?
    let createdAt: Date?
}

nonisolated
struct DeviceListResponse: Decodable, Sendable {
    let devices: [DeviceTokenResponse]
}
