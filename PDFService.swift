//
//  PDFComposer.swift
//  app_357_Loan
//
//  Created by VTN on 26/10/24.
//

import Foundation
import UIKit
import SafariServices

class PDFService {
    static func renderHtmlFromResource(templateResource: String, delegate: PDFServiceDelegate) -> String? {
        guard let path = Bundle.main.path(forResource: templateResource, ofType: "html") else {
            return nil
        }
        do {
            let template = try String(contentsOfFile: path)
            
            return renderHtmlFromTemplate(template: template, delegate: delegate)
        }
        catch {
            return nil
        }
    }
    
    static func renderHtmlFromTemplate(template: String, delegate: PDFServiceDelegate) -> String {
        var parsedTemplate = template
        
        let regions = parseRegionsInTemplate(&parsedTemplate)
        
        return parseRegion(parsedTemplate, delegate: delegate, regions: regions)
    }
    
    private static func parseRegion(_ region: String, delegate: PDFServiceDelegate, regions: [String: String], index: Int = 0) -> String {
        var result = replaceValuesOfTemplate(region, delegate: delegate, index: index)
        result = replaceItemsInTemplate(result, delegate: delegate, regions: regions, index: index)
        return result
    }
    
    private static func replaceValuesOfTemplate(_ template: String, delegate: PDFServiceDelegate, index: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<field name=\"(.*?)\"\\/>", options: .caseInsensitive) else {
            return template
        }
        
        let str = template as NSString
        let matches = regex.matches(in: template, options: [], range: NSRange(location: 0, length: str.length)).map {
            (str.substring(with: $0.range), str.substring(with: $0.range(at: 1)))
        }
        
        var result = template
        for match in matches {
            let value = delegate.valueForParameter(parameter: match.1, index: index)
            result = result.replacingOccurrences(of: match.0, with: value, options: .literal, range: nil)
        }
        
        return result
    }
    
    private static func replaceItemsInTemplate(_ template: String, delegate: PDFServiceDelegate, regions: [String: String], index: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<item name=\"(.*)\"\\/>", options: .caseInsensitive) else {
            return template
        }
        
        let str = template as NSString
        let matches = regex.matches(in: template, options: [], range: NSRange(location: 0, length: str.length)).map {
            (str.substring(with: $0.range), str.substring(with: $0.range(at: 1)))
        }
        
        var result = template
        for match in matches {
            let items = delegate.itemsForParameter(parameter: match.1, index: index)
            var value = ""
            for (i, item) in items.enumerated() {
                guard let region = regions[match.1] else { continue }
                value += parseRegion(region, delegate: item, regions: regions, index: i)
            }
            result = result.replacingOccurrences(of: match.0, with: value, options: .literal, range: nil)
        }
        
        return result
    }
    
    private static func parseRegionsInTemplate(_ template: inout String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: "(?s)<region name=\"(.*?)\">(.*?)<\\/region>", options: .caseInsensitive) else {
            return [:]
        }
        
        let str = template as NSString
        let matches = regex.matches(in: template, options: [], range: NSRange(location: 0, length: str.length)).map {
            (str.substring(with: $0.range), str.substring(with: $0.range(at: 1)))
        }
        
        var result = [String: String]()
        
        for match in matches {
            template = template.replacingOccurrences(of: match.0, with: "", options: .literal, range: nil)
            result[match.1] = match.0
                .replacingOccurrences(of: "<region name=\"\(match.1)\">", with: "")
                .replacingOccurrences(of: "</region>", with: "")
        }
        
        return result
    }
    
    static func exportHTMLContentToPDFFile(htmlContent: String) -> String? {
        guard let pdfData = exportHTMLContentToPDF(htmlContent: htmlContent) else {
            return nil
        }
        
        let docDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let pdfFilename = "\(docDir)/PDFExport.pdf"

        pdfData.write(toFile: pdfFilename, atomically: true)

        print("successfully saved pdf at: \(pdfFilename)")
        return pdfFilename
    }

    static func sharePdf(htmlContent: String) {
        let pdfUrl = exportHTMLContentToPDFFile(htmlContent: htmlContent) ?? ""
        guard let document = NSData(contentsOfFile: pdfUrl) else {
            return
        }
        let activityVC = UIActivityViewController(activityItems: [document], applicationActivities: nil)
        UIApplication.getTopViewController()?.present(activityVC, animated: true, completion: nil)
    }

    static func exportHTMLContentToPDF(htmlContent: String) -> NSData? {
        let printPageRenderer = CustomPrintPageRenderer()

        // Deactivated until UIMarkupTextPrintFormatter is available in Catalyst
//        let printFormatter = UIMarkupTextPrintFormatter(markupText: htmlContent)
//        printPageRenderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
        
        guard let printData = htmlContent.data(using: String.Encoding.utf8) else {
            return nil
        }
        
        do {
            let printText = try NSAttributedString(data: printData, options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],  documentAttributes: nil)

            let printFormatter = UISimpleTextPrintFormatter(attributedText: printText)

            printPageRenderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
            
            return drawPDFUsingPrintPageRenderer(printPageRenderer: printPageRenderer)
        }
        catch
        {
            return nil
        }
    }
    
    private static func drawPDFUsingPrintPageRenderer(printPageRenderer: UIPrintPageRenderer) -> NSData {
        let data = NSMutableData()
        
        UIGraphicsBeginPDFContextToData(data, CGRect.zero, nil)
        printPageRenderer.prepare(forDrawingPages: NSMakeRange(0, printPageRenderer.numberOfPages))
        
        let bounds = UIGraphicsGetPDFContextBounds()
        
        for i in 0...(printPageRenderer.numberOfPages - 1) {
            UIGraphicsBeginPDFPage()
            printPageRenderer.drawPage(at: i, in: bounds)
        }
        
        UIGraphicsEndPDFContext();
        return data
    }
}

import WebKit

class PDFPreview: UIViewController, WKUIDelegate {

    private var webView: WKWebView?

    private(set) var delegate: PDFServiceDelegate?
    private(set) var resource: String?
    private(set) var htmlContent: String?
    
    override func loadView() {
        super.loadView()
        
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView!.uiDelegate = self
        view = webView
        
        if let htmlContent = htmlContent {
            loadPreviewFromHtml(htmlContent: htmlContent)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.statusBarStyle = .default
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.statusBarStyle = .lightContent
    }
    
    public func loadPreviewFromHtmlTemplateResource(templateResource: String, delegate: PDFServiceDelegate) throws {
        guard let htmlContent = PDFService.renderHtmlFromResource(templateResource: templateResource, delegate: delegate) else {
            print("Could not load html template resource: \(templateResource)")
            throw NSError()
        }
        
        self.delegate = delegate
        self.resource = templateResource
        
        loadPreviewFromHtml(htmlContent: htmlContent)
    }
    
    public func loadPreviewFromHtmlTemplate(htmlTemplate: String, delegate: PDFServiceDelegate) {
        let htmlContent = PDFService.renderHtmlFromTemplate(template: htmlTemplate, delegate: delegate)
        
        self.delegate = delegate
        
        loadPreviewFromHtml(htmlContent: htmlContent)
    }
    
    public func loadPreviewFromHtml(htmlContent: String) {
        self.htmlContent = htmlContent
        
        if let webView = webView {
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
    
    @IBAction func cancelButtonTapped(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func exportButtonTapped(_ sender: UIBarButtonItem) {
        guard let htmlContent = htmlContent, let pdfData = PDFService.exportHTMLContentToPDF(htmlContent: htmlContent) else {
            print("could not save.")
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [pdfData], applicationActivities: nil)

        activityVC.completionWithItemsHandler = {(activityType: UIActivity.ActivityType?, completed: Bool, returnedItems: [Any]?, error: Error?) in
            if completed {
                self.dismiss(animated: true, completion: nil)
            }
        }
        
        self.present(activityVC, animated: true, completion: nil)
        activityVC.popoverPresentationController?.barButtonItem = sender
    }
}

public class PDFPreviewController: UINavigationController {
    public static func instantiate() -> PDFPreviewController {
        return UIStoryboard(name: "PDFPreview", bundle: Bundle(for: self)).instantiateInitialViewController() as! PDFPreviewController
    }
    
    private var pdfPreview: PDFPreview? {
        return topViewController as? PDFPreview
    }
    
    public func loadPreviewFromHtmlTemplateResource(templateResource: String, delegate: PDFServiceDelegate) throws {
        try pdfPreview?.loadPreviewFromHtmlTemplateResource(templateResource: templateResource, delegate: delegate)
    }
    
    public func loadPreviewFromHtmlTemplate(htmlTemplate: String, delegate: PDFServiceDelegate) {
        pdfPreview?.loadPreviewFromHtmlTemplate(htmlTemplate: htmlTemplate, delegate: delegate)
    }
    
    public func loadPreviewFromHtml(htmlContent: String) {
        pdfPreview?.loadPreviewFromHtml(htmlContent: htmlContent)
    }
}

class CustomPrintPageRenderer: UIPrintPageRenderer {
    
    let A4PageWidth: CGFloat = 595.2
    let A4PageHeight: CGFloat = 841.8
    
    override init() {
        super.init()
        
        // Specify the frame of the A4 page.
        let pageFrame = CGRect(x: 0.0, y: 0.0, width: A4PageWidth, height: A4PageHeight)
        
        // Set the page frame.
        self.setValue(NSValue(cgRect: pageFrame), forKey: "paperRect")
        
        // Set the horizontal and vertical insets (that's optional).
//        self.setValue(NSValue(cgRect: pageFrame), forKey: "printableRect") // No Inset
        self.setValue(NSValue(cgRect: pageFrame.insetBy(dx: 10, dy: 10)), forKey: "printableRect") // Inset

    }
}

public protocol PDFServiceDelegate {
    func valueForParameter(parameter: String, index: Int) -> String
    func itemsForParameter(parameter: String, index: Int) -> [PDFServiceDelegate]
}
