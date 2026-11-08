import XCTest
import ReviewCore
@testable import EvidenceWorkbench
private struct AutomaticTransport: ResponsesTransport {
    func send(_ request: URLRequest) async throws -> (Data,Int,String?) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String:Any]
        let format = (body["text"] as! [String:Any])["format"] as! [String:Any]
        let name = format["name"] as! String
        var payload: [String:Any]
        if name == "article_extraction" {
            let schema = String(data:try JSONSerialization.data(withJSONObject:format["schema"]!),encoding:.utf8)!
            payload = ["observations":schema.contains("age_mean") ? [["variable_id":"age_mean","value":"74.61","missingness":"reported","arm":"Control","comparator":"","outcome":"","timepoint":"Baseline","subgroup":"","analysis":"","quote":"Control mean age 74.61 years at baseline.","page":1,"confidence":95,"note":""]] : []]
        } else if name == "independent_source_check" {
            let input = body["input"] as! [[String:Any]];let content = input[0]["content"] as! [[String:Any]];let text = content[0]["text"] as! String
            let claimsText = text.components(separatedBy:"UNVERIFIED CLAIMS:\n")[1].components(separatedBy:"\nORIGINAL SOURCE TEXT:")[0]
            let claims = try JSONSerialization.jsonObject(with:Data(claimsText.utf8)) as! [[String:String]]
            payload = ["checks":claims.map { ["observation_id":$0["id"]!,"verdict":"supported","reason":"Control mean age, years, baseline match.","source_quote":"Control mean age 74.61 years at baseline."] }]
        } else { throw WorkbenchError.invalid("Unexpected network operation in automatic text workflow") }
        let text=String(data:try JSONSerialization.data(withJSONObject:payload),encoding:.utf8)!
        let envelope:[String:Any] = ["id":"resp_offline_test","status":"completed","output":[["type":"message","content":[["type":"output_text","text":text]]]]]
        return (try JSONSerialization.data(withJSONObject:envelope),200,nil)
    }
}
@MainActor final class AutomaticWorkflowTests:XCTestCase {
    func testAutomaticPipelineCreatesLabeledDatasetWithoutHumanVerificationOrOverwrite() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let repo=ProjectRepository(root:root);var project=ReviewProject();var plan=ReviewPlan()
        plan.researchQuestion="Q";plan.picott.population="Adults";plan.picott.intervention="Drug";plan.picott.comparator="Control";plan.picott.outcomes="Age";plan.picott.timing="Baseline";plan.picott.studyTypes="RCT";plan.reviewer="QA";plan.extractionProcess="Automatic AI review";plan.riskOfBiasTool="RoB2";plan.synthesisPlan="Narrative";plan.approvedAt=Date();project.plan=plan
        let installed=try await repo.installDocument(data:Data("Control mean age 74.61 years at baseline.".utf8),extension:"txt",projectID:project.id)
        let doc=SourceDocument(filename:"trial.txt",relativePath:installed.path,sha256:installed.hash,pages:[.init(number:1,text:"Control mean age 74.61 years at baseline.")]);project.documents=[doc];_ = try await repo.save(project)
        let store=WorkspaceStore(root:root,client:OpenAIClient(transport:AutomaticTransport()),cloud:.init(isEnabled:{true},apiKey:{"synthetic"}));await store.loadProjects()
        store.extract(documentID:doc.id,automaticReview:true);await store.operation?.value
        XCTAssertNil(store.errorMessage);XCTAssertEqual(store.current?.observations.first { $0.variableID=="age_mean" }?.status,.aiReviewed)
        XCTAssertFalse(store.current!.observations.contains { $0.status == .verified })
        let exports=root.appendingPathComponent(project.id.uuidString).appendingPathComponent("exports")
        let first=try FileManager.default.contentsOfDirectory(at:exports,includingPropertiesForKeys:nil);XCTAssertEqual(first.count,1)
        let data=try Data(contentsOf:first[0].appendingPathComponent("ai-reviewed.csv"));XCTAssertTrue(String(decoding:data,as:UTF8.self).contains("74.61"))
        XCTAssertTrue(FileManager.default.fileExists(atPath:first[0].appendingPathComponent("manifest.json").path))
        store.extract(documentID:doc.id,automaticReview:true);await store.operation?.value
        XCTAssertNil(store.errorMessage);XCTAssertEqual(try FileManager.default.contentsOfDirectory(at:exports,includingPropertiesForKeys:nil).count,2)
        XCTAssertEqual(try Data(contentsOf:first[0].appendingPathComponent("ai-reviewed.csv")),data)
    }
}
