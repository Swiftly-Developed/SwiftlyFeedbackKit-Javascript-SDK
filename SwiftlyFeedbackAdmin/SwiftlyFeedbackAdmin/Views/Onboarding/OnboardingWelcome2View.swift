//
//  OnboardingWelcome2View.swift
//  SwiftlyFeedbackAdmin
//
//  Welcome Step 2: Collect Feedback
//

import SwiftUI

struct OnboardingWelcome2View: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    let onLogin: () -> Void

    private let features: [(icon: String, title: String, description: String)] = [
        ("lightbulb.fill", "Feature Requests", "Let users suggest new features and improvements"),
        ("ladybug.fill", "Bug Reports", "Capture issues with device info and screenshots")
    ]

    var body: some View {
        OnboardingWelcomeStepView(
            icon: "bubble.left.and.bubble.right.fill",
            iconColors: [.blue, .cyan],
            title: "Collect Feedback",
            subtitle: "Gather feature requests and bug reports directly from your app",
            features: features,
            primaryButtonTitle: "Continue",
            onContinue: onContinue,
            onBack: onBack,
            onLogin: onLogin
        )
    }
}

#Preview {
    OnboardingWelcome2View(
        onContinue: {},
        onBack: {},
        onLogin: {}
    )
}
