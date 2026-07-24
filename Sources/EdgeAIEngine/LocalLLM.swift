import Foundation

public struct LLMOptions: Equatable {
    public let maxTokens: Int
    public let temperature: Double

    public init(maxTokens: Int = 512, temperature: Double = 0.2) {
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

public protocol LocalLLM {
    func complete(prompt: String, options: LLMOptions) async throws -> String
}

public struct ExtractiveLocalLLM: LocalLLM {
    public init() {}

    public func complete(prompt: String, options: LLMOptions) async throws -> String {
        let context = PromptSections.extractContext(from: prompt)
        let question = PromptSections.extractQuestion(from: prompt)
        let questionTokens = Set(Tokenizer.tokens(in: question))
        let isActionItemQuestion = !questionTokens.intersection(["action", "actions", "item", "items", "task", "tasks", "todo"]).isEmpty
        let allCandidates = candidatePassages(context)
        let bulletCandidates = allCandidates.filter { isBullet($0) }
        let candidates = isActionItemQuestion && !bulletCandidates.isEmpty ? bulletCandidates : allCandidates

        let ranked = candidates
            .map { sentence -> (String, Int) in
                var overlap = Set(Tokenizer.tokens(in: sentence)).intersection(questionTokens).count
                if isActionItemQuestion && isBullet(sentence) {
                    overlap += 3
                }
                return (sentence, overlap)
            }
            .filter { !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { left, right in
                if left.1 == right.1 { return left.0.count > right.0.count }
                return left.1 > right.1
            }
            .prefix(4)
            .map(\.0)

        if ranked.isEmpty {
            return "I could not find enough local context to answer that. Add relevant files to the index or lower the retrieval threshold."
        }

        return """
        Offline extractive answer:
        \(ranked.map { "- \(stripBulletMarker($0))" }.joined(separator: "\n"))

        Note: this answer used the built-in deterministic fallback. Start a local llama.cpp server and pass --llama-server for generative answers.
        """
    }

    private func candidatePassages(_ text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map(cleanContextLine)
            .filter { !$0.isEmpty }
            .filter { !isCitationHeader($0) }

        let bulletLines = lines.filter { $0.hasPrefix("-") || $0.hasPrefix("•") }
        let sentences = lines
            .joined(separator: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return unique(bulletLines + sentences)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }

        return result
    }

    private func isBullet(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("-") || trimmed.hasPrefix("•")
    }

    private func stripBulletMarker(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private func cleanContextLine(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("#") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private func isCitationHeader(_ value: String) -> Bool {
        value.hasPrefix("[") && value.contains("—")
    }
}

public final class LlamaCppServerClient: LocalLLM {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func complete(prompt: String, options: LLMOptions) async throws -> String {
        let url = baseURL.appendingPathComponent("completion")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "prompt": prompt,
            "n_predict": options.maxTokens,
            "temperature": options.temperature
        ])

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw LlamaCppServerError.httpStatus(httpResponse.statusCode)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw LlamaCppServerError.invalidResponse
        }

        if let content = dictionary["content"] as? String {
            return content
        }

        if let choices = dictionary["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        throw LlamaCppServerError.invalidResponse
    }

    public func healthCheck() async -> LlamaCppServerHealth {
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let body = String(data: data.prefix(512), encoding: .utf8)
            let reachable = statusCode.map { (200..<300).contains($0) } ?? false

            return LlamaCppServerHealth(
                baseURL: baseURL.absoluteString,
                reachable: reachable,
                statusCode: statusCode,
                detail: reachable ? "llama.cpp server responded to /health." : (body ?? "llama.cpp server did not return a successful /health response.")
            )
        } catch {
            return LlamaCppServerHealth(
                baseURL: baseURL.absoluteString,
                reachable: false,
                statusCode: nil,
                detail: String(describing: error)
            )
        }
    }
}

public struct LlamaCppServerHealth: Codable, Equatable {
    public let baseURL: String
    public let reachable: Bool
    public let statusCode: Int?
    public let detail: String

    public init(baseURL: String, reachable: Bool, statusCode: Int?, detail: String) {
        self.baseURL = baseURL
        self.reachable = reachable
        self.statusCode = statusCode
        self.detail = detail
    }
}

public enum LlamaCppServerError: Error, CustomStringConvertible {
    case httpStatus(Int)
    case invalidResponse

    public var description: String {
        switch self {
        case .httpStatus(let status):
            return "llama.cpp server returned HTTP \(status)."
        case .invalidResponse:
            return "llama.cpp server response did not include generated content."
        }
    }
}

enum PromptSections {
    static func extractContext(from prompt: String) -> String {
        extractSection("Context:", until: "Question:", from: prompt)
    }

    static func extractQuestion(from prompt: String) -> String {
        extractSection("Question:", until: "Answer", from: prompt)
    }

    private static func extractSection(_ start: String, until end: String, from prompt: String) -> String {
        guard let startRange = prompt.range(of: start) else { return prompt }
        let afterStart = prompt[startRange.upperBound...]
        guard let endRange = afterStart.range(of: end) else {
            return String(afterStart)
        }
        return String(afterStart[..<endRange.lowerBound])
    }
}
