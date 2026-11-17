import Foundation
import CryptoKit
import PDFKit

/// Server-owned publication authority, separate from PDFKit geometry and text.
struct NativeOriginalPagePublication: Codable, Equatable {
    let schemaVersion: Int
    let capability: String
    let documentID: String
    let serviceID: String
    let revision: String
    let requestID: String
    let viewID: String
    let generation: Int
    let publicationID: String
    let sequence: Int
    let inputFingerprint: String
    let htmlInputFingerprint: String
    let pdfInputFingerprint: String
    let pdfSHA256: String
    let byteCount: Int
    let resource: String
    let sourceAnchors: String
    let delivery: String

    func validate(context: NativeReaderRequestContext) throws {
        guard schemaVersion == 1, capability == "original-pdf-full-v1",
              documentID == context.target.documentID, serviceID == context.target.serviceID,
              revision == context.target.revision, generation == context.generation,
              requestID == context.requestID.uuidString.lowercased(), viewID == context.viewID.uuidString.lowercased(),
              UUID(uuidString: publicationID) != nil, sequence > 0, sequence < 9_007_199_254_740_992,
              byteCount > 0, byteCount <= 16 * 1024 * 1024,
              [inputFingerprint, htmlInputFingerprint, pdfInputFingerprint, pdfSHA256].allSatisfy({
                $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }),
              resource == "api/native-pages/\(publicationID)/\(sequence).pdf",
              sourceAnchors == "unsupported", delivery == "immutable-pdf-full-reset" else {
            throw NativeOriginalPageError.binding
        }
    }
}

struct NativeOriginalPageDelivery {
    let publication: NativeOriginalPagePublication
    let data: Data
    /// Only local geometry inspection occurs here; it cannot create a publication.
    func supplement(context: NativeReaderRequestContext, viewGeneration: Int) async throws -> NativeOriginalPageSupplement {
        try publication.validate(context: context)
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == publication.pdfSHA256,
                  data.count == publication.byteCount,
                  let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider),
                  !pdf.isEncrypted, (1...2048).contains(pdf.numberOfPages) else { throw NativeOriginalPageError.binding }
            var geometries = [NativeOriginalPageGeometry]()
            for i in 0..<pdf.numberOfPages {
                try Task.checkCancellation()
                guard let page = pdf.page(at: i + 1) else { throw NativeOriginalPageError.invalidPDF }
                geometries.append(NativeOriginalPageGeometry(index: i, mediaBox: page.getBoxRect(.mediaBox),
                    cropBox: page.getBoxRect(.cropBox), rotation: Int(page.rotationAngle)))
            }
            return NativeOriginalPageSupplement(binding: NativeOriginalPageBinding(identity: context.target,
                inputFingerprint: publication.inputFingerprint, snapshotGeneration: publication.sequence,
                requestGeneration: context.generation, viewID: context.viewID, viewGeneration: viewGeneration,
                publicationSequence: publication.sequence, pdfSHA256: publication.pdfSHA256, pages: geometries), data: data)
        }.value
    }
}

actor NativeReaderOriginalPageTransport {
    private let transport: NativeReaderTransport
    private var active: NativeReaderRequestContext?
    private var last: NativeOriginalPagePublication?
    private var disposed = false
    init(transport: NativeReaderTransport) { self.transport = transport }
    func invalidate() { active = nil }
    func dispose() { disposed = true; active = nil }
    func pages(for context: NativeReaderRequestContext) async throws -> NativeOriginalPageDelivery {
        guard !disposed else { throw NativeOriginalPageError.cancelled }
        active = context
        var fields = try await transport.fields(context)
        fields["capabilities"] = ["original-pdf-full-v1"]
        let request = try await transport.request(path: "api/native-pages", fields: fields, get: true)
        let response = try await transport.network.send(request, 65536)
        try await transport.validate(response, limit: 65536)
        let publication = try JSONDecoder().decode(NativeOriginalPagePublication.self, from: response.data)
        try publication.validate(context: context)
        if let last {
            guard last.serviceID == publication.serviceID, last.publicationID == publication.publicationID,
                  publication.sequence >= last.sequence,
                  publication.sequence != last.sequence ||
                    (last.pdfSHA256 == publication.pdfSHA256 && last.inputFingerprint == publication.inputFingerprint && last.revision == publication.revision)
            else { throw NativeOriginalPageError.stale }
        }
        let resource = try await transport.request(path: publication.resource, fields: fields, get: true)
        let pdf = try await transport.network.send(resource, publication.byteCount)
        try Task.checkCancellation()
        guard !disposed, active == context else { throw NativeOriginalPageError.stale }
        guard pdf.status == 200, pdf.headers["content-type"] == "application/pdf",
              pdf.data.count == publication.byteCount,
              SHA256.hash(data: pdf.data).map({ String(format: "%02x", $0) }).joined() == publication.pdfSHA256 else {
            throw NativeOriginalPageError.binding
        }
        // Actor reentrancy: a newer request can advance while resource IO waits.
        if let last, publication.sequence < last.sequence { throw NativeOriginalPageError.stale }
        last = publication
        return NativeOriginalPageDelivery(publication: publication, data: pdf.data)
    }
}
