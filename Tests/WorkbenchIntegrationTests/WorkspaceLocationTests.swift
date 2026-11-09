import XCTest
@testable import EvidenceWorkbench
final class WorkspaceLocationTests: XCTestCase {
    func testReviewAndQAAlwaysAvoidProductionDefault() {
        let normal = URL(fileURLWithPath:"/production/reviews")
        for identifier in ["com.example.Review","com.example.QA"] {
            let root = WorkspaceLocation.resolve(arguments:[],bundleURL:URL(fileURLWithPath:"/isolated/dist/Review.app"),identifier:identifier,isolated:false,configuredQA:nil,normal:normal)
            XCTAssertEqual(root.path,"/isolated/dist/ReviewData");XCTAssertNotEqual(root,normal)
        }
    }
    func testExplicitWorkspaceAndReleaseQAConfigurationAreHonored() {
        let normal=URL(fileURLWithPath:"/production/reviews")
        XCTAssertEqual(WorkspaceLocation.resolve(arguments:["app","--workspace","/test/data"],bundleURL:URL(fileURLWithPath:"/test/Review.app"),identifier:"com.example.Review",isolated:true,configuredQA:nil,normal:normal).path,"/test/data")
        XCTAssertEqual(WorkspaceLocation.resolve(arguments:[],bundleURL:URL(fileURLWithPath:"/test/QA.app"),identifier:"com.example.QA",isolated:false,configuredQA:"/designated/qa",normal:normal).path,"/designated/qa")
    }
}
