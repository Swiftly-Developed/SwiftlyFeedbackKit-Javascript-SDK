//
//  OnboardingWelcome3View.swift
//  SwiftlyFeedbackAdmin
//
//  Welcome Step 3: Integrations & Team
//

import SwiftUI

struct OnboardingWelcome3View: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    let onLogin: () -> Void

    private let features: [(icon: String, title: String, description: String)] = [
        ("arrow.triangle.branch", "Integrations", "Sync with GitHub, Linear, Notion, Slack & more"),
        ("person.3.fill", "Team Collaboration", "Invite team members and work together")
    ]

    var body: some View {
        OnboardingWelcomeStepView(
            icon: "square.stack.3d.up.fill",
            iconColors: [.purple, .pink],
            title: "Powerful Workflow",
            subtitle: "Connect your favorite tools and collaborate with your team",
            features: features,
            primaryButtonTitle: "Create Account",
            onContinue: onContinue,
            onBack: onBack,
            onLogin: onLogin
        )
    }
}

#Preview {
    OnboardingWelcome3View(
        onContinue: {},
        onBack: {},
        onLogin: {}
    )
}
