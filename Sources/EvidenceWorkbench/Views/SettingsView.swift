import SwiftUI

struct SettingsView: View {
    @AppStorage("reviewerName") private var reviewer = ""
    @AppStorage("cloudAIEnabled") private var cloudEnabled = false
    @AppStorage("extractionModel") private var extractionModel = "gpt-4.1"
    @AppStorage("researchModel") private var researchModel = "o3"
    @AppStorage("sourceCheckModel") private var sourceCheckModel = "gpt-4.1"
    @AppStorage("visualExtraction") private var visualExtraction = true
    @AppStorage("huggingFaceTableConsent") private var huggingFaceTables = false
    @AppStorage("apiKeyFile") private var keyFilePreference = ""
    @AppStorage("tableOCRAllowOpenAIFallback") private var tableFallback = false
    @AppStorage("localPaddleTables") private var localPaddle = false
    @AppStorage("localPaddleEndpoint") private var paddleEndpoint = "http://127.0.0.1:8766/table"
    @State private var hfToken = ""
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
                    Text("Credential source: local key file \(file.lastPathComponent). It takes precedence; the Keychain entry is used only if this file lacks OPENAI_API_KEY.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Credential source: macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Choose local key file…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.showsHiddenFiles = true; panel.message = "Choose the approved OPENAI_API_KEY env file. Its contents will not be copied or displayed."
                        if panel.runModal() == .OK, let url = panel.url { UserDefaults.standard.set(url.path, forKey: "apiKeyFile"); keyFilePreference = url.path; message = "Local key file configured." }
                    }
                    if !keyFilePreference.isEmpty {
                        Button("Use Keychain instead") { UserDefaults.standard.removeObject(forKey: "apiKeyFile"); keyFilePreference = ""; message = "Key file preference removed. The Keychain entry (or a .env.local beside a source build) is used." }
                    }
                    Button(checking ? "Checking…" : "Check OpenAI connection") {
                        checking = true
                        Task { message = await AppCredentials.checkConnection(); checking = false }
                    }.disabled(checking)
                }
                Toggle("Allow sending selected content to OpenAI", isOn: $cloudEnabled)
                Text("Planning sends protocols, the saved plan and recent chat. Extraction sends article page text, field definitions and, when enabled, page images. The independent source check sends each AI claim (value and context), the cited page text with its neighbours and the same page images. Table and image discovery sends page images; table conversion sends the boxed image. Deep research sends protocols and the saved plan/question, and uses web search plus server-side background storage. Local planning, manual extraction, OCR and export work offline.").font(.caption).foregroundStyle(.secondary)
                Toggle("Include original PDF page images in extraction", isOn: $visualExtraction)
                Text("Visual extraction sends up to three page images per batch alongside text. Image-only findings remain unverified until their source can be anchored.").font(.caption).foregroundStyle(.secondary)
                SecureField("OpenAI API key", text: $key)
                HStack {
                    Button("Save key in Keychain") { do { try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); key = ""; message = "Key saved in macOS Keychain. Live API access has not been tested." } catch { message = error.localizedDescription } }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove saved key", role: .destructive) { do { try KeychainStore.delete(); message = "Saved key removed." } catch { message = error.localizedDescription } }
                }
                if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            }
            Section("Measured OCR hybrid") {
                Text("Apple Vision stays local for OCR. The real-article pilot found that specialist table OCR preserves structure better than text-only OCR; it is not a broad scientific accuracy guarantee.").font(.caption).foregroundStyle(.secondary)
                Toggle("Use local PaddleOCR-VL-1.6 tables (takes priority)", isOn: $localPaddle)
                TextField("Local Paddle endpoint", text: $paddleEndpoint)
                Text("Best table latency in the small GPU pilot. Requires a separately started local service; no weights are downloaded by this app. The supplied service uses CUDA and has not been validated on Apple Silicon. If unavailable, tables remain unresolved; no remote fallback is applied to local mode.").font(.caption).foregroundStyle(.secondary)
                Toggle("Use GLM-OCR tables and allow sending table images to Hugging Face", isOn: $huggingFaceTables)
                SecureField("Optional Hugging Face token for Space quota", text: $hfToken)
                HStack {
                    Button("Save Hugging Face token") { do { try KeychainStore.save(hfToken.trimmingCharacters(in: .whitespacesAndNewlines),provider:"huggingface");hfToken="";message="Hugging Face token saved separately in Keychain." } catch {message=error.localizedDescription} }.disabled(hfToken.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    Button("Remove Hugging Face token") { do {try KeychainStore.delete(provider:"huggingface");message="Hugging Face token removed."}catch{message=error.localizedDescription} }
                }
                Toggle("If GLM is unavailable, allow OpenAI table transcription", isOn: $tableFallback)
                Text("Fallback requires OpenAI content consent and an API key. Each fallback table is labeled with its actual provider. With fallback off, unavailable tables stay unresolved. The connected ChatGPT Hugging Face account does not automatically provide a token to this app.").font(.caption).foregroundStyle(.secondary)
                Text("Optional GLM-OCR uses a community Hugging Face Space, a separate recipient from OpenAI. No OpenAI key is needed for this table path. Public service quotas/availability can interrupt work; no silent provider switch is made. Leave off to retain the existing OpenAI table path. Article extraction and source checks still use your configured OpenAI models.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Model settings") {
                TextField("Extraction & planning", text: $extractionModel)
                TextField("Deep research", text: $researchModel)
                TextField("Independent source checker", text: $sourceCheckModel)
                if sourceCheckModel.trimmingCharacters(in: .whitespaces) == extractionModel.trimmingCharacters(in: .whitespaces) {
                    Label("The source checker is the same model as the extractor. Its agreement is correlated with the extractor's errors; choose a different compatible model for a more independent check.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                Text("Extraction, source checking, asset discovery and table transcription use separate bounded request contexts. The checker receives the claim, the plan definition and unit, and the original source only, never the extractor's note or confidence. Multiple AI passes do not guarantee correctness.").font(.caption).foregroundStyle(.secondary)
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
