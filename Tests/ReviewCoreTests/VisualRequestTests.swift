import XCTest
@testable import ReviewCore

extension OpenAIClientTests {
    func testSourceCheckerRejectsMissingOrForeignClaimIDs() async throws {
        let transport = MockTransport([(try envelope(text: "{\"checks\":[]}"), 200)])
        let row = Observation(documentID: UUID(), variableID: "n", value: "235")
        do { _ = try await OpenAIClient(transport: transport).checkSources(observations: [row], variables: CoreFields.defaults, pages: [.init(number: 1, text: "235")], images: [], model: "checker", apiKey: "test"); XCTFail("Missing check must not pass") } catch {}
        let body = try await transport.body()
        XCTAssertTrue((body["instructions"] as? String)?.contains("separate context") == true)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertFalse((content.first?["text"] as? String ?? "").contains("\"confidence\":"))
    }
    func testAssetDiscoveryRejectsUnrelatedPhysicalPage() async throws {
        let reply = "{\"assets\":[{\"kind\":\"figure\",\"page\":99,\"label\":\"Fig 1\",\"title\":\"Flow\",\"caption\":\"\",\"warnings\":[]}]}"
        let transport = MockTransport([(try envelope(text: reply), 200)])
        do { _ = try await OpenAIClient(transport: transport).discoverAssets(images: [.init(page: 4, dataURL: "data:image/jpeg;base64,AA==")], model: "test", apiKey: "test"); XCTFail("Wrong page must fail") } catch {}
    }
    func testExtractionSchemaForbidsMissingStatusWithNonemptyValue() async throws {
        let transport = MockTransport([(try envelope(text: "{\"observations\":[]}"), 200)])
        _ = try await OpenAIClient(transport: transport).extract(pages: [], variables: [CoreFields.defaults[0]], plan: ReviewPlan(), model: "test", apiKey: "test")
        let body = try await transport.body()
        let text = try XCTUnwrap(body["text"] as? [String: Any]); let format = try XCTUnwrap(text["format"] as? [String: Any]); let schema = try XCTUnwrap(format["schema"] as? [String: Any]); let props = try XCTUnwrap(schema["properties"] as? [String: Any]); let rows = try XCTUnwrap(props["observations"] as? [String: Any]); let item = try XCTUnwrap(rows["items"] as? [String: Any]); let choices = try XCTUnwrap(item["anyOf"] as? [[String: Any]])
        XCTAssertEqual(choices.count, 2)
        let observed = try XCTUnwrap(choices[0]["properties"] as? [String: [String: Any]])
        let missing = try XCTUnwrap(choices[1]["properties"] as? [String: [String: Any]])
        XCTAssertEqual(observed["missingness"]?["enum"] as? [String], ["reported"])
        XCTAssertEqual(missing["value"]?["enum"] as? [String], [""])
        XCTAssertFalse((missing["missingness"]?["enum"] as? [String] ?? []).contains("reported"))
    }
    func testTableTranscriptionFixesColumnCountBeforeReadingCells() async throws {
        let transport = MockTransport([(try envelope(text: "{\"title\":\"Table 1\",\"columns\":[\"Group\",\"N\"],\"warnings\":[]}"), 200), (try envelope(text: "{\"rows\":[{\"cells\":[\"Control\",\"235\"]}],\"footnotes\":[],\"warnings\":[]}"), 200)])
        let table = try await OpenAIClient(transport: transport).transcribeTable(image: .init(page: 7, dataURL: "data:image/jpeg;base64,AA=="), model: "test", apiKey: "test")
        XCTAssertEqual(table.columns, ["Group", "N"]); XCTAssertEqual(table.rows[0].cells, ["Control", "235"])
        let body = try await transport.body()
        let text = try XCTUnwrap(body["text"] as? [String: Any]); let format = try XCTUnwrap(text["format"] as? [String: Any]); let schema = try XCTUnwrap(format["schema"] as? [String: Any]); let properties = try XCTUnwrap(schema["properties"] as? [String: Any]); let rows = try XCTUnwrap(properties["rows"] as? [String: Any]); let row = try XCTUnwrap(rows["items"] as? [String: Any]); let cells = try XCTUnwrap((row["properties"] as? [String: Any])?["cells"] as? [String: Any])
        XCTAssertEqual(cells["minItems"] as? Int, 2); XCTAssertEqual(cells["maxItems"] as? Int, 2)
    }
    func testVisualExtractionSendsTextAndLabeledImage() async throws {
        let transport = MockTransport([(try envelope(text: "{\"observations\":[]}"), 200)])
        _ = try await OpenAIClient(transport: transport).extract(pages: [.init(number: 7, text: "Table data")], variables: [CoreFields.defaults[0]], plan: ReviewPlan(), model: "test", apiKey: "test", pageImages: [.init(page: 7, dataURL: "data:image/jpeg;base64,AA==")])
        let body = try await transport.body()
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 3)
        XCTAssertEqual(content[1]["text"] as? String, "Original PDF page 7")
        XCTAssertEqual(content[2]["type"] as? String, "input_image")
        XCTAssertEqual(content[2]["detail"] as? String, "high")
    }
    func testImageFromUnrequestedPageIsRejectedBeforeTransmission() async throws {
        let transport = MockTransport([])
        do {
            _ = try await OpenAIClient(transport: transport).extract(pages: [.init(number: 1, text: "Data")], variables: [CoreFields.defaults[0]], plan: ReviewPlan(), model: "test", apiKey: "test", pageImages: [.init(page: 2, dataURL: "data:image/jpeg;base64,AA==")])
            XCTFail("Wrong page must not be sent")
        } catch {}
        let count = await transport.count(); XCTAssertEqual(count, 0)
    }
}
