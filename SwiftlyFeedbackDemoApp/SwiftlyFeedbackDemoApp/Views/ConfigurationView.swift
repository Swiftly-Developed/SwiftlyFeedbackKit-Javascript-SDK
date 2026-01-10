import SwiftUI

struct ConfigurationView: View {
    var settings: AppSettings

    var body: some View {
        List {
            userSection
            subscriptionSection
            permissionsSection
            sdkConfigurationSection
            voteNotificationsSection
            displayOptionsSection
        }
        .navigationTitle("Settings")
    }

    // MARK: - User Section

    @ViewBuilder
    private var userSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.userName.isEmpty ? "Anonymous User" : settings.userName)
                        .font(.headline)

                    Text(settings.userEmail.isEmpty ? "No email set" : settings.userEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)

            TextField("Your Name", text: Bindable(settings).userName)
                .textContentType(.name)
                .autocorrectionDisabled()

            TextField("Email Address", text: Bindable(settings).userEmail)
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            TextField("Custom User ID (optional)", text: Bindable(settings).customUserId)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        } header: {
            Text("Profile")
        } footer: {
            Text("Your email is used when submitting feedback and voting so you can receive status update notifications. Custom User ID links feedback to your account system.")
        }
    }

    // MARK: - Subscription Section

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            HStack {
                Text("Amount")
                Spacer()
                TextField("0.00", value: Bindable(settings).subscriptionAmount, format: .currency(code: "USD"))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }

            Picker("Billing Cycle", selection: Bindable(settings).subscriptionType) {
                ForEach(SubscriptionType.allCases) { type in
                    Text(type.displayName).tag(type as SubscriptionType)
                }
            }

            if settings.subscriptionAmount > 0 && settings.subscriptionType != .none {
                HStack {
                    Text("Monthly MRR")
                    Spacer()
                    Text(calculatedMRR, format: .currency(code: "USD"))
                        .foregroundStyle(.blue)
                        .fontWeight(.medium)
                }
            }
        } header: {
            Text("Subscription")
        } footer: {
            Text("Optional: Set your subscription details for MRR tracking. This helps app developers understand which users are most valuable.")
        }
    }

    private var calculatedMRR: Double {
        switch settings.subscriptionType {
        case .none: return 0
        case .weekly: return settings.subscriptionAmount * (52.0 / 12.0)
        case .monthly: return settings.subscriptionAmount
        case .quarterly: return settings.subscriptionAmount / 3.0
        case .yearly: return settings.subscriptionAmount / 12.0
        }
    }

    // MARK: - SDK Configuration Section

    @ViewBuilder
    private var sdkConfigurationSection: some View {
        Section {
            Toggle("Allow Undo Vote", isOn: Bindable(settings).allowUndoVote)

            Toggle("Show Comment Section", isOn: Bindable(settings).showCommentSection)

            Toggle("Show Email Field", isOn: Bindable(settings).showEmailField)
        } header: {
            Text("Features")
        } footer: {
            Text("Configure which features are enabled in the feedback interface.")
        }
    }

    // MARK: - Vote Notifications Section

    @ViewBuilder
    private var voteNotificationsSection: some View {
        Section {
            Toggle("Show Vote Email Dialog", isOn: Bindable(settings).showVoteEmailField)

            Toggle("Default Opt-In to Notifications", isOn: Bindable(settings).voteNotificationDefaultOptIn)

            if !settings.userEmail.isEmpty {
                HStack {
                    Text("Current Email")
                    Spacer()
                    Text(settings.userEmail)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Vote Notifications")
        } footer: {
            if settings.userEmail.isEmpty {
                Text("When email is not set in Profile, users see a dialog to optionally enter their email when voting. With email set, votes automatically use it.")
            } else {
                Text("Email is configured. Votes will automatically use '\(settings.userEmail)' for status notifications (no dialog shown).")
            }
        }
    }

    // MARK: - Permissions Section

    @ViewBuilder
    private var permissionsSection: some View {
        Section {
            Toggle("Allow Feedback Submission", isOn: Bindable(settings).allowFeedbackSubmission)

            if !settings.allowFeedbackSubmission {
                TextField("Custom disabled message", text: Bindable(settings).feedbackSubmissionDisabledMessage, axis: .vertical)
                    .lineLimit(2...4)
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Disable feedback submission for free users. When disabled, tapping the add button shows an alert instead of opening the submission form.")
        }
    }

    // MARK: - Display Options Section

    @ViewBuilder
    private var displayOptionsSection: some View {
        Section {
            Toggle("Show Status Badge", isOn: Bindable(settings).showStatusBadge)

            Toggle("Show Category Badge", isOn: Bindable(settings).showCategoryBadge)

            Toggle("Show Vote Count", isOn: Bindable(settings).showVoteCount)

            Toggle("Expand Description in List", isOn: Bindable(settings).expandDescriptionInList)
        } header: {
            Text("Display Options")
        } footer: {
            Text("Customize how feedback items are displayed in the list.")
        }
    }
}

#Preview {
    ConfigurationView(settings: AppSettings())
}
