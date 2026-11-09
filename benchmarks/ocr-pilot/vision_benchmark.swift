import Foundation
import Vision
import ImageIO
import Darwin
let args = CommandLine.arguments
var results: [[String: Any]] = []
for path in args.dropFirst() {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Unreadable canonical image") }
    for repeatIndex in 0..<2 {
        let start = Date()
        let request = VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection = true;request.automaticallyDetectsLanguage = true
        var record: [String: Any] = ["engine":"apple-vision","sample":URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent,"repeat":repeatIndex,"vision_revision":request.revision]
        do {
            try VNImageRequestHandler(cgImage:image).perform([request])
            let lines = (request.results ?? []).map { item -> [String:Any] in
                let box=item.boundingBox
                return ["text":item.topCandidates(1).first?.string ?? "","x":box.minX,"y":box.minY,"width":box.width,"height":box.height]
            }
            record["lines"]=lines;record["text"]=lines.compactMap { $0["text"] as? String }.joined(separator:"\n")
        } catch { record["error"]=error.localizedDescription }
        record["elapsed_seconds"]=Date().timeIntervalSince(start)
        var usage = rusage();getrusage(RUSAGE_SELF,&usage);record["process_peak_rss_bytes"]=usage.ru_maxrss
        results.append(record)
    }
}
let data=try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]);FileHandle.standardOutput.write(data)
