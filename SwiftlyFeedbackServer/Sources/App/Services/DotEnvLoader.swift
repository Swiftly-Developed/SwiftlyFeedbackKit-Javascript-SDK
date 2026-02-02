import Foundation

/// Loads environment variables from a `.env` file for local development.
/// Does NOT overwrite existing environment variables (Heroku config vars take precedence).
enum DotEnvLoader {
    /// Loads environment variables from `.env` file in the current working directory.
    /// - Returns: Number of variables loaded, or nil if file doesn't exist.
    @discardableResult
    static func load(path: String = ".env") -> Int? {
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let envPath = currentDirectory + "/" + path

        guard fileManager.fileExists(atPath: envPath) else {
            return nil
        }

        guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return nil
        }

        var loadedCount = 0
        let lines = contents.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Parse KEY=VALUE
            guard let equalsIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)

            // Remove surrounding quotes if present
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            // Only set if not already defined (existing env vars take precedence)
            if ProcessInfo.processInfo.environment[key] == nil {
                setenv(key, value, 0)
                loadedCount += 1
            }
        }

        return loadedCount
    }
}
