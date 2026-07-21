import Foundation

enum ConversationProviderSettings {
    struct ModelOption: Identifiable, Hashable {
        let id: String
        let title: String
        let supportsImages: Bool
    }

    static let providerPreferenceKey = "voiceDeck.conversationProvider"
    private static let credentialConfiguredPrefix = "voiceDeck.providerCredentialConfigured."
    static func modelPreferenceKey(for providerID: ConversationProviderID) -> String {
        "voiceDeck.conversationModel.\(providerID.rawValue)"
    }

    static var selectedProviderID: ConversationProviderID {
        let rawValue = UserDefaults.standard.string(forKey: providerPreferenceKey)
        guard let providerID = rawValue.flatMap(ConversationProviderID.init(rawValue:)),
              availableProviderIDs.contains(providerID) else {
            return .qwen
        }
        return providerID
    }

    static let availableProviderIDs: [ConversationProviderID] = [.qwen, .openAI, .kimi, .glm]

    static func defaultModel(for providerID: ConversationProviderID) -> String {
        modelOptions(for: providerID).first?.id ?? ""
    }

    static func modelOptions(for providerID: ConversationProviderID) -> [ModelOption] {
        switch providerID {
        case .qwen:
            [
                .init(id: "qwen3-vl-plus", title: "Qwen3 VL Plus", supportsImages: true),
                .init(id: "qwen3-vl-flash", title: "Qwen3 VL Flash", supportsImages: true),
                .init(id: "qwen-vl-plus", title: "Qwen VL Plus", supportsImages: true)
            ]
        case .openAI:
            [
                .init(id: "gpt-5-mini", title: "GPT-5 mini（图像）", supportsImages: true),
                .init(id: "gpt-5.1", title: "GPT-5.1（图像）", supportsImages: true),
                .init(id: "gpt-4.1-mini", title: "GPT-4.1 mini（图像）", supportsImages: true)
            ]
        case .kimi:
            [
                .init(id: "kimi-k2.5", title: "Kimi K2.5", supportsImages: true)
            ]
        case .glm:
            [
                .init(id: "glm-4.6v-flash", title: "GLM-4.6V Flash", supportsImages: true)
            ]
        case .miniMax:
            []
        }
    }

    static func defaultEndpoint(for providerID: ConversationProviderID) -> String {
        switch providerID {
        case .qwen:
            qwenWorkspaceEndpoint ?? "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .openAI: "https://api.openai.com/v1/chat/completions"
        case .kimi: "https://api.moonshot.cn/v1/chat/completions"
        case .glm: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .miniMax: "https://api.minimaxi.com/v1/chat/completions"
        }
    }

    private static var qwenWorkspaceEndpoint: String? {
        let workspaceID = UserDefaults.standard.string(forKey: "voiceDeck.dashScopeWorkspaceID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard workspaceID.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
            return nil
        }
        return "https://\(workspaceID).cn-beijing.maas.aliyuncs.com/compatible-mode/v1/chat/completions"
    }

    static func keychainReference(for providerID: ConversationProviderID) -> String {
        providerID == .qwen ? KeychainKey.dashScopeAPIKey.rawValue : "conversation.\(providerID.rawValue).api-key"
    }

    static func savedModel(for providerID: ConversationProviderID) -> String {
        let savedModel = UserDefaults.standard.string(forKey: modelPreferenceKey(for: providerID))
        return modelOptions(for: providerID).contains(where: { $0.id == savedModel }) ? savedModel! : defaultModel(for: providerID)
    }

    static func selectedModelOption(for providerID: ConversationProviderID) -> ModelOption {
        modelOptions(for: providerID).first { $0.id == savedModel(for: providerID) }
            ?? ModelOption(id: "", title: "", supportsImages: false)
    }

    static func save(model: String, for providerID: ConversationProviderID) {
        guard modelOptions(for: providerID).contains(where: { $0.id == model }) else { return }
        UserDefaults.standard.set(model, forKey: modelPreferenceKey(for: providerID))
    }

    static func select(model: String, for providerID: ConversationProviderID) {
        UserDefaults.standard.set(providerID.rawValue, forKey: providerPreferenceKey)
        save(model: model, for: providerID)
    }

    static func markCredentialSaved(for providerID: ConversationProviderID) {
        UserDefaults.standard.set(true, forKey: credentialConfiguredPrefix + providerID.rawValue)
    }

    static func hasSavedCredential(for providerID: ConversationProviderID) -> Bool {
        UserDefaults.standard.bool(forKey: credentialConfiguredPrefix + providerID.rawValue)
    }

    static func configuration() throws -> ConversationModelConfiguration {
        let providerID = selectedProviderID
        let model = savedModel(for: providerID).trimmingCharacters(in: .whitespacesAndNewlines)
        return try ConversationModelConfiguration(
            providerID: providerID,
            model: model.isEmpty ? defaultModel(for: providerID) : model,
            endpoint: URL(string: defaultEndpoint(for: providerID)),
            authentication: .apiKey(reference: keychainReference(for: providerID))
        )
    }

    static func capabilities(for providerID: ConversationProviderID) -> ConversationProviderCapabilities {
        var capabilities: ConversationProviderCapabilities = [.text, .streaming]
        if selectedModelOption(for: providerID).supportsImages {
            capabilities.insert(.images)
        }
        return capabilities
    }
}
