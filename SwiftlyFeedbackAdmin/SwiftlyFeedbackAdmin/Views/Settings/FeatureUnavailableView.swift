//
//  FeatureUnavailableView.swift
//  SwiftlyFeedbackAdmin
//
//  Apple-compliant view shown when a feature is not available for the user's account.
//  Does not prompt for subscription to comply with App Store guidelines.
//

import SwiftUI

struct FeatureUnavailableView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                // Message
                VStack(spacing: 8) {
                    Text("Feature Unavailable")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("This feature is not available for your account.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    FeatureUnavailableView()
}
