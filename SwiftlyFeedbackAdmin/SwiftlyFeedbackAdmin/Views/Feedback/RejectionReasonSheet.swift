import SwiftUI

struct RejectionReasonSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var rejectionReason: String
    let onReject: (String?) -> Void

    @FocusState private var isTextEditorFocused: Bool

    private let maxCharacterCount = 500

    private var trimmedReason: String {
        rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasReason: Bool {
        !trimmedReason.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerSection

                Divider()

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Provide a reason to help users understand why their feedback was rejected. This will be included in the notification email.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        textEditorSection
                    }
                    .padding()
                }

                Divider()

                // Actions
                footerSection
            }
            .navigationTitle("Reject Feedback")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Slight delay to ensure the view is fully presented
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextEditorFocused = true
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 400)
        #endif
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Reject Feedback")
                .font(.headline)
        }
        .padding()
    }

    // MARK: - Text Editor Section

    private var textEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rejection Reason")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            TextEditor(text: $rejectionReason)
                .font(.body)
                .frame(minHeight: 120)
                .focused($isTextEditorFocused)
                .scrollContentBackground(.hidden)
                #if os(macOS)
                .background(Color(nsColor: .controlBackgroundColor))
                #else
                .background(Color(.secondarySystemGroupedBackground))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: rejectionReason) { _, newValue in
                    if newValue.count > maxCharacterCount {
                        rejectionReason = String(newValue.prefix(maxCharacterCount))
                    }
                }

            HStack {
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(rejectionReason.count)/\(maxCharacterCount)")
                    .font(.caption)
                    .foregroundStyle(rejectionReason.count >= maxCharacterCount ? Color.red : Color.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 12) {
            // Primary action - Reject with reason (only enabled if there's a reason)
            Button {
                onReject(trimmedReason)
                dismiss()
            } label: {
                Text("Reject with Reason")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!hasReason)

            // Secondary action - Reject without reason
            Button {
                onReject(nil)
                dismiss()
            } label: {
                Text("Reject Without Reason")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Empty") {
    RejectionReasonSheet(
        rejectionReason: .constant(""),
        onReject: { reason in
            print("Rejected with reason: \(reason ?? "none")")
        }
    )
}

#Preview("With Reason") {
    RejectionReasonSheet(
        rejectionReason: .constant("This feature doesn't align with our current product roadmap. We may revisit this in the future."),
        onReject: { reason in
            print("Rejected with reason: \(reason ?? "none")")
        }
    )
}
