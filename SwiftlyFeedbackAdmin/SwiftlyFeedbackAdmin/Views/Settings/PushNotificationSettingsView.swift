//
//  PushNotificationSettingsView.swift
//  SwiftlyFeedbackAdmin
//

import SwiftUI
import UserNotifications

struct PushNotificationSettingsView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var pushManager = PushNotificationManager.shared

    @State private var isRequestingPermission = false
    @State private var isUpdating = false
    @State private var showPermissionDeniedAlert = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        Form {
            // System Permission Section
            systemPermissionSection

            // Master Toggle Section (only when authorized)
            if pushManager.authorizationStatus == .authorized ||
               pushManager.authorizationStatus == .provisional {
                masterToggleSection
            }

            // Notification Types Section (only when master toggle is on)
            if pushManager.authorizationStatus == .authorized ||
               pushManager.authorizationStatus == .provisional {
                if authViewModel.currentUser?.pushNotificationsEnabled == true {
                    notificationTypesSection
                }
            }

            // Device Info Section
            if pushManager.isRegistered {
                deviceSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 400)
        #else
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        #endif
        .navigationTitle("Push Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await pushManager.checkAuthorizationStatus()
        }
        .alert("Notifications Disabled", isPresented: $showPermissionDeniedAlert) {
            Button("Open Settings") {
                openSystemSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Push notifications are disabled in system settings. Please enable them to receive updates.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unexpected error occurred")
        }
    }

    // MARK: - System Permission Section

    @ViewBuilder
    private var systemPermissionSection: some View {
        Section {
            systemPermissionRow
        } header: {
            Text("System Permission")
        } footer: {
            Text("Push notifications require system permission. Once enabled, you can customize which events trigger notifications.")
        }
    }

    @ViewBuilder
    private var systemPermissionRow: some View {
        switch pushManager.authorizationStatus {
        case .notDetermined:
            Button {
                requestPermission()
            } label: {
                HStack(spacing: 12) {
                    iconBadge(icon: "bell.badge", color: .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Push Notifications")
                            .foregroundStyle(.primary)
                        Text("Tap to request permission")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isRequestingPermission {
                        ProgressView()
                            #if os(macOS)
                            .scaleEffect(0.7)
                            #endif
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRequestingPermission)

        case .authorized, .provisional:
            HStack(spacing: 12) {
                iconBadge(icon: "bell.badge.fill", color: .green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications Enabled")
                    Text("System permission granted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
            }

        #if os(iOS)
        case .ephemeral:
            HStack(spacing: 12) {
                iconBadge(icon: "bell.badge.fill", color: .green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications Enabled")
                    Text("Temporary permission granted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
            }
        #endif

        case .denied:
            Button {
                showPermissionDeniedAlert = true
            } label: {
                HStack(spacing: 12) {
                    iconBadge(icon: "bell.slash.fill", color: .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications Disabled")
                            .foregroundStyle(.primary)
                        Text("Tap to open system settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Settings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        @unknown default:
            HStack(spacing: 12) {
                iconBadge(icon: "questionmark.circle", color: .gray)
                Text("Unknown Status")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Master Toggle Section

    @ViewBuilder
    private var masterToggleSection: some View {
        Section {
            Toggle(isOn: masterToggleBinding) {
                HStack(spacing: 12) {
                    iconBadge(icon: "bell.badge", color: .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable All Notifications")
                        Text("Master switch for all push notifications")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isUpdating)
        } header: {
            Text("Global Setting")
        } footer: {
            if authViewModel.currentUser?.pushNotificationsEnabled == false {
                Text("Turn this on to enable push notifications and configure individual notification types below.")
            }
        }
    }

    private var masterToggleBinding: Binding<Bool> {
        Binding(
            get: { authViewModel.currentUser?.pushNotificationsEnabled ?? true },
            set: { newValue in
                Task {
                    await updateSetting(
                        pushNotificationsEnabled: newValue
                    )
                }
            }
        )
    }

    // MARK: - Notification Types Section

    @ViewBuilder
    private var notificationTypesSection: some View {
        Section {
            // New Feedback
            notificationToggle(
                icon: "bubble.left.fill",
                color: .blue,
                title: "New Feedback",
                description: "When users submit new feedback",
                isOn: Binding(
                    get: { authViewModel.currentUser?.pushNotifyNewFeedback ?? true },
                    set: { newValue in
                        Task { await updateSetting(pushNotifyNewFeedback: newValue) }
                    }
                )
            )

            // New Comments
            notificationToggle(
                icon: "text.bubble.fill",
                color: .indigo,
                title: "New Comments",
                description: "When someone comments on feedback",
                isOn: Binding(
                    get: { authViewModel.currentUser?.pushNotifyNewComments ?? true },
                    set: { newValue in
                        Task { await updateSetting(pushNotifyNewComments: newValue) }
                    }
                )
            )

            // New Votes
            notificationToggle(
                icon: "hand.thumbsup.fill",
                color: .orange,
                title: "New Votes",
                description: "When feedback receives new votes",
                isOn: Binding(
                    get: { authViewModel.currentUser?.pushNotifyVotes ?? true },
                    set: { newValue in
                        Task { await updateSetting(pushNotifyVotes: newValue) }
                    }
                )
            )

            // Status Changes
            notificationToggle(
                icon: "arrow.triangle.2.circlepath",
                color: .purple,
                title: "Status Changes",
                description: "When feedback status is updated",
                isOn: Binding(
                    get: { authViewModel.currentUser?.pushNotifyStatusChanges ?? true },
                    set: { newValue in
                        Task { await updateSetting(pushNotifyStatusChanges: newValue) }
                    }
                )
            )
        } header: {
            Text("Notification Types")
        } footer: {
            Text("Choose which events should trigger push notifications. You can also customize these settings per-project in project settings.")
        }
    }

    @ViewBuilder
    private func notificationToggle(
        icon: String,
        color: Color,
        title: String,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                iconBadge(icon: icon, color: color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isUpdating)
    }

    // MARK: - Device Section

    @ViewBuilder
    private var deviceSection: some View {
        Section {
            HStack(spacing: 12) {
                iconBadge(icon: deviceIcon, color: .gray)

                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName)
                    if let token = pushManager.deviceToken {
                        Text(String(token.prefix(24)) + "...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Registered Device")
        } footer: {
            Text("This device is registered to receive push notifications from Feedback Kit.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func iconBadge(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
    }

    private func requestPermission() {
        isRequestingPermission = true
        Task {
            let granted = await pushManager.requestAuthorization()
            isRequestingPermission = false

            if !granted {
                showPermissionDeniedAlert = true
            }
        }
    }

    private func updateSetting(
        pushNotificationsEnabled: Bool? = nil,
        pushNotifyNewFeedback: Bool? = nil,
        pushNotifyNewComments: Bool? = nil,
        pushNotifyVotes: Bool? = nil,
        pushNotifyStatusChanges: Bool? = nil
    ) async {
        guard authViewModel.currentUser != nil else { return }

        isUpdating = true
        defer { isUpdating = false }

        let request = UpdateNotificationSettingsRequest(
            notifyNewFeedback: nil,
            notifyNewComments: nil,
            pushNotificationsEnabled: pushNotificationsEnabled,
            pushNotifyNewFeedback: pushNotifyNewFeedback,
            pushNotifyNewComments: pushNotifyNewComments,
            pushNotifyVotes: pushNotifyVotes,
            pushNotifyStatusChanges: pushNotifyStatusChanges
        )

        do {
            let updatedUser: User = try await AdminAPIClient.shared.patch(
                path: "auth/notifications",
                body: request,
                requiresAuth: true
            )
            authViewModel.currentUser = updatedUser
        } catch {
            AppLogger.api.error("Failed to update notification settings: \(error)")
            errorMessage = "Failed to update settings. Please try again."
            showError = true
        }
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private var deviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "This Mac"
        #else
        return "This Device"
        #endif
    }

    private var deviceIcon: String {
        #if os(iOS)
        // Detect device type more specifically
        if UIDevice.current.userInterfaceIdiom == .pad {
            return "ipad"
        } else {
            return "iphone"
        }
        #elseif os(macOS)
        return "laptopcomputer"
        #else
        return "desktopcomputer"
        #endif
    }
}

#Preview {
    NavigationStack {
        PushNotificationSettingsView(authViewModel: AuthViewModel())
    }
}
