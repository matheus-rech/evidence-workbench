import XCTest
import PDFKit
import ReviewCore
@testable import EvidenceWorkbench

/// Real API release-acceptance check on complete single-page excerpts, not an article-wide accuracy benchmark.
@MainActor final class LiveAutomaticPilotTests:XCTestCase {
    func testRealArticleExcerptsCompleteAutomaticWorkflow() async throws {
        let env=ProcessInfo.processInfo.environment
        guard let keyPath=env["EW_AUTOMATIC_KEY_FILE"],let sourceRoot=env["EW_AUTOMATIC_SOURCE_ROOT"],let outputRoot=env["EW_AUTOMATIC_OUTPUT"] else { throw XCTSkip("Paid, opt-in real automatic pipeline acceptance test.") }
        let root=URL(fileURLWithPath:outputRoot);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let defaults=UserDefaults.standard;let previous=defaults.object(forKey:"huggingFaceTableConsent");defaults.set(true,forKey:"huggingFaceTableConsent");defer{if let previous{defaults.set(previous,forKey:"huggingFaceTableConsent")}else{defaults.removeObject(forKey:"huggingFaceTableConsent")}}
        let oldLocal=defaults.object(forKey:"localPaddleTables");defaults.set(false,forKey:"localPaddleTables");defer{if let oldLocal{defaults.set(oldLocal,forKey:"localPaddleTables")}else{defaults.removeObject(forKey:"localPaddleTables")}}
        let oldFallback=defaults.object(forKey:"tableOCRAllowOpenAIFallback");defaults.set(true,forKey:"tableOCRAllowOpenAIFallback");defer{if let oldFallback{defaults.set(oldFallback,forKey:"tableOCRAllowOpenAIFallback")}else{defaults.removeObject(forKey:"tableOCRAllowOpenAIFallback")}}
        let repository=ProjectRepository(root:root.appendingPathComponent("reviews"));var project=ReviewProject(title:"REAL automatic acceptance · primary-paper page excerpts")
        var plan=ReviewPlan();plan.researchQuestion="Describe the printed participant and outcome characteristics in these explicitly labeled primary-paper page excerpts. Missingness refers only to the excerpt."
        plan.picott.population="Adults with atrial fibrillation";plan.picott.intervention="Clinical decision support";plan.picott.comparator="Control/usual care";plan.picott.outcomes="Printed patient and adherence characteristics";plan.picott.timing="Baseline and reported follow-up";plan.picott.studyTypes="Cluster randomized primary reports"
        plan.reviewer="Automatic acceptance test, not independent human verification";plan.extractionProcess="AI extraction, independent-context source check and GLM-OCR table transcription; no human verified observations.";plan.riskOfBiasTool="No RoB judgment from a page excerpt";plan.synthesisPlan="No pooling; numeric and source audit only";plan.approvedAt=Date();project.plan=plan
        var documents:[SourceDocument]=[]
        for (name,page) in [("Arts_2017",7),("Karlsson_2018",10)] {
            let original=try XCTUnwrap(PDFDocument(url:URL(fileURLWithPath:sourceRoot).appendingPathComponent(name+".pdf")))
            let excerpt=PDFDocument();excerpt.insert(try XCTUnwrap(original.page(at:page-1)?.copy() as? PDFPage),at:0)
            let bytes=try XCTUnwrap(excerpt.dataRepresentation());let local=root.appendingPathComponent(name+"_physical_page_\(page)_excerpt.pdf");try bytes.write(to:local)
            let loaded=try await DocumentLoader.load(local,ocr:true);let installed=try await repository.installDocument(data:bytes,extension:"pdf",projectID:project.id)
            let doc=SourceDocument(filename:local.lastPathComponent,relativePath:installed.path,sha256:installed.hash,pages:loaded.pages,warnings:["Benchmark excerpt of original physical page \(page). Do not infer article-wide absence."]);documents.append(doc)
        }
        project.documents=documents;_ = try await repository.save(project)
        let store=WorkspaceStore(root:root.appendingPathComponent("reviews"),cloud:.init(isEnabled:{true},apiKey:{try LocalKeyFile.read(URL(fileURLWithPath:keyPath))}));await store.loadProjects()
        var summaries:[[String:Any]]=[]
        for doc in documents {
            let start=Date();store.extract(documentID:doc.id,automaticReview:true);await store.operation?.value
            XCTAssertNil(store.errorMessage,store.errorMessage ?? "")
            let latest=try XCTUnwrap(store.current);let rows=latest.observations.filter{$0.documentID==doc.id};let assets=(latest.assets ?? []).filter{$0.documentID==doc.id}
            XCTAssertEqual(assets.filter{$0.kind == .table}.count,assets.filter{$0.table != nil}.count,"Every discovered table must be transcribed in this acceptance fixture.");XCTAssertFalse(assets.isEmpty);XCTAssertTrue((store.notice ?? "").contains("Automatic output prepared"));
            XCTAssertFalse(rows.isEmpty);XCTAssertFalse(rows.contains{$0.status == .verified})
            let report:[String:Any] = ["source":doc.filename,"elapsed_seconds":Date().timeIntervalSince(start),"observations":rows.count,"ai_reviewed":rows.filter{$0.status == .aiReviewed}.count,"assets":assets.count,"tables":assets.filter{$0.table != nil}.count,"asset_warnings":assets.flatMap(\.warnings),"notice":store.notice ?? "","error":store.errorMessage ?? ""]
            summaries.append(report)
            let data=try JSONEncoder().encode(latest);try data.write(to:root.appendingPathComponent("project-after-"+doc.filename+".json"))
            try JSONSerialization.data(withJSONObject:summaries,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("summary.json"))
        }
    }
}
