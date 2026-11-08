import SwiftUI

struct SettingsView: View {
    @AppStorage("reviewerName") private var reviewer = ""
    @AppStorage("cloudAIEnabled") private var cloudEnabled = false
    @AppStorage("extractionModel") private var extractionModel = "gpt-4.1"
    @AppStorage("researchModel") private var researchModel = "o3"
    @AppStorage("sourceCheckModel") private var sourceCheckModel = "gpt-4.1"
    @AppStorage("visualExtraction") private var visualExtraction = true
    @State private var key = ""
    @State private var message = ""
    @State private var checking = false
    @State private var models: [String] = []
    var body: some View {
        Form {
            Section("Reviewer") {
                TextField("Default reviewer name", text: $reviewer)
                Text("New reviews use this name. Each review retains its own approving reviewer in the plan.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Cloud AI") {
                if let file = AppCredentials.keyFileURL {
                    Text("Local credential file configured: \(file.lastPathComponent)").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Choose local key file…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true; panel.message = "Choose the approved OPENAI_API_KEY env file. Its contents will not be copied or displayed."
                        if panel.runModal() == .OK, let url = panel.url { UserDefaults.standard.set(url.path, forKey: "apiKeyFile"); message = "Local key file configured." }
                    }
                    Button(checking ? "Checking…" : "Check OpenAI connection") {
                        checking = true
                        Task { message = await AppCredentials.checkConnection(); checking = false }
                    }.disabled(checking)
                }
                Toggle("Allow sending selected content to OpenAI", isOn: $cloudEnabled)
                Text("Planning sends protocols, the saved plan and recent chat. Extraction sends article page text and definitions. Deep research sends protocols and the saved plan/question, and uses web search plus server-side background storage. Local planning, manual extraction, OCR and export work offline.").font(.caption).foregroundStyle(.secondary)
                Toggle("Include original PDF page images in extraction", isOn: $visualExtraction)
                Text("Visual extraction sends up to three page images per batch alongside text. Image-only findings remain unverified until their source can be anchored.").font(.caption).foregroundStyle(.secondary)
                SecureField("OpenAI API key", text: $key)
                HStack {
                    Button("Save key in Keychain") { do { try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); key = ""; message = "Key saved in macOS Keychain. Live API access has not been tested." } catch { message = error.localizedDescription } }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove saved key", role: .destructive) { do { try KeychainStore.delete(); message = "Saved key removed." } catch { message = error.localizedDescription } }
                }
                if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            }
            Section("Model settings") {
                TextField("Extraction & planning", text: $extractionModel)
                TextField("Deep research", text: $researchModel)
                TextField("Independent source checker", text: $sourceCheckModel)
                Text("Extraction, source checking, asset discovery and table transcription use separate bounded request contexts. The checker can use a different compatible model. Multiple AI passes do not guarantee correctness.").font(.caption).foregroundStyle(.secondary)
                Button("Load account model list") {
                    checking = true
                    Task {
                        do { models = try await AppCredentials.availableModels(); message = "Account model list loaded. Select models supporting the required features." }
                        catch { message = "Could not load models. Check API connection and project permissions." }
                        checking = false
                    }
                }.disabled(checking)
                if !models.isEmpty {
                    Picker("Account model for extraction", selection: $extractionModel) {
                        if !models.contains(extractionModel) { Text(extractionModel + " (not listed)").tag(extractionModel) }
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    if !models.contains(extractionModel) { Text("The selected extraction model was not returned by this account. Choose a listed model before extracting.").font(.caption).foregroundStyle(.orange) }
                }
                Text("Extraction requires Responses API structured outputs. Research requires a reasoning model supporting high effort, web_search and background responses. API use may incur charges; access depends on your account.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(16)
    }
}
