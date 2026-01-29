import Fluent

struct AddStripeSubscriptionFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            // Add Stripe fields
            .field("stripe_customer_id", .string)
            .field("stripe_subscription_id", .string)
            // Add Apple transaction ID for StoreKit 2
            .field("apple_original_transaction_id", .string)
            // Track subscription source
            .field("subscription_source", .string) // "stripe" | "app_store"
            .update()

        // Remove RevenueCat field in a separate update
        try await database.schema("users")
            .deleteField("revenuecat_app_user_id")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            // Remove Stripe fields
            .deleteField("stripe_customer_id")
            .deleteField("stripe_subscription_id")
            .deleteField("apple_original_transaction_id")
            .deleteField("subscription_source")
            .update()

        // Add back RevenueCat field
        try await database.schema("users")
            .field("revenuecat_app_user_id", .string)
            .update()
    }
}
