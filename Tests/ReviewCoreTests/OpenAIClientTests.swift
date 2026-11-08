import XCTest
@testable import ReviewCore

actor MockTransport: ResponsesTransport {
    var responses: [(Data, Int, String?)]
    var requests: [URLRequest] = []
    init(_ objects: [(String, Int)]) { responses = objects.map { (Data($0.0.utf8), $0.1, nil) } }
    func send(_ request: URLRequest) async throws -> (Data, Int, String?) { requests.append(request); return responses.removeFirst() }
    func body() throws -> [String: Any] { try JSONSerialization.jsonObject(with: requests.last!.httpBody!) as! [String: Any] }
    func count() -> Int { requests.count }
}

final class OpenAIClientTests: XCTestCase {
    func envelope(text: String, status: String = "completed") throws -> String {
        let object: [String: Any] = ["id": "resp_test", "status": status, "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    func testStructuredExtractionUsesSchemaAndNoServerStorage() async throws {
        let transport = MockTransport([(try envelope(text: "{\"observations\":[]}"), 200)])
        let client = OpenAIClient(transport: transport)
        let result = try await client.extract(pages: [.init(number: 1, text: "No relevant data")], variables: [CoreFields.defaults[0]], plan: ReviewPlan(), model: "test-model", apiKey: "test-not-a-real-key")
        XCTAssertTrue(result.observations.isEmpty)
        let body = try await transport.body()
        XCTAssertEqual(body["store"] as? Bool, false)
        let text = body["text"] as? [String: Any]; let format = text?["format"] as? [String: Any]
        XCTAssertEqual(format?["strict"] as? Bool, true)
        XCTAssertTrue((body["instructions"] as? String)?.contains("untrusted DATA") == true)
    }
    func testIncompleteOutputIsRejectedBeforeApplying() async throws {
        let transport = MockTransport([(try envelope(text: "{\"observations\":[]}", status: "incomplete"), 200)])
        do { _ = try await OpenAIClient(transport: transport).extract(pages: [], variables: [CoreFields.defaults[0]], plan: ReviewPlan(), model: "test", apiKey: "test"); XCTFail("Incomplete should fail") } catch {}
    }
    func testMalformedOutputIsRejected() async throws {
        let transport = MockTransport([(try envelope(text: "not json"), 200)])
        do { _ = try await OpenAIClient(transport: transport).extract(pages: [], variables: [CoreFields.defaults[0]], plan: ReviewPlan(), model: "test", apiKey: "test"); XCTFail("Malformed should fail") } catch {}
    }
    func testUnauthorizedDoesNotEchoResponseBodyOrRetry() async throws {
        let transport = MockTransport([("sensitive-server-body", 401)])
        do { _ = try await OpenAIClient(transport: transport).extract(pages: [], variables: [CoreFields.defaults[0]], plan: ReviewPlan(), model: "test", apiKey: "test"); XCTFail("401 should fail") }
        catch { XCTAssertFalse(error.localizedDescription.contains("sensitive-server-body")) }
        let count = await transport.count(); XCTAssertEqual(count, 1)
    }
    func testResearchUsesWebSearchAndPersistsResponseID() async throws {
        let transport = MockTransport([("{\"id\":\"resp_research\",\"status\":\"queued\",\"output\":[]}", 200)])
        let job = try await OpenAIClient(transport: transport).startResearch(project: ReviewProject(), question: "Relevant outcomes", model: "research-test", apiKey: "test")
        XCTAssertEqual(job.responseID, "resp_research")
        let body = try await transport.body()
        XCTAssertEqual(body["background"] as? Bool, true); XCTAssertEqual(body["store"] as? Bool, true)
        XCTAssertEqual((body["tools"] as? [[String: String]])?.first?["type"], "web_search")
    }
    func testCitationsComeFromAnnotationsNotInventedLinks() throws {
        let response = try JSONDecoder().decode(ResponsesEnvelope.self, from: Data("{\"status\":\"completed\",\"output\":[{\"content\":[{\"type\":\"output_text\",\"text\":\"report\",\"annotations\":[{\"type\":\"url_citation\",\"url\":\"https://example.org/paper\",\"title\":\"Paper\"},{\"type\":\"url_citation\",\"url\":\"javascript:alert(1)\",\"title\":\"Unsafe\"}]}]}]}".utf8))
        XCTAssertEqual(response.sources.count, 1); XCTAssertEqual(response.sources[0].title, "Paper")
    }
}
