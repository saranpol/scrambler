// Alamofire.swift
//
// Copyright (c) 2014 Alamofire (http://alamofire.org)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

// HTTP Method Definitions; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html
public enum Method: String {
    case OPTIONS = "OPTIONS"
    case GET = "GET"
    case HEAD = "HEAD"
    case POST = "POST"
    case PUT = "PUT"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
    case TRACE = "TRACE"
    case CONNECT = "CONNECT"
}

public enum ParameterEncoding {
    case URL
    case JSON
    case PropertyList(NSPropertyListFormat, NSPropertyListWriteOptions)
    case Custom((NSURLRequest, [String: AnyObject]?) -> (NSURLRequest, NSError?))

    public func encode(request: NSURLRequest, parameters: [String: AnyObject]?) -> (NSURLRequest, NSError?) {
        if parameters == nil {
            return (request, nil)
        }

        var mutableRequest: NSMutableURLRequest! = request.mutableCopy() as NSMutableURLRequest
        var error: NSError? = nil

        switch self {
        case .URL:
            func query(parameters: [String: AnyObject]) -> String {
                var components: [(String, String)] = []
                for key in sorted(Array(parameters.keys), <) {
                    let value: AnyObject! = parameters[key]
                    components += queryComponents(key, value)
                }

                return join("&", components.map{"\($0)=\($1)"} as [String])
            }

            func encodesParametersInURL(method: Method) -> Bool {
                switch method {
                case .GET, .HEAD, .DELETE:
                    return true
                default:
                    return false
                }
            }

            if encodesParametersInURL(Method.fromRaw(request.HTTPMethod!)!) {
                let URLComponents = NSURLComponents(URL: mutableRequest.URL!, resolvingAgainstBaseURL: false)
                URLComponents.query = (URLComponents.query != nil ? URLComponents.query! + "&" : "") + query(parameters!)
                mutableRequest.URL = URLComponents.URL
            } else {
                if mutableRequest.valueForHTTPHeaderField("Content-Type") == nil {
                    mutableRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }

                mutableRequest.HTTPBody = query(parameters!).dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)
            }
        case .JSON:
            let options = NSJSONWritingOptions.allZeros
            if let data = NSJSONSerialization.dataWithJSONObject(parameters!, options: options, error: &error) {
                mutableRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                mutableRequest.HTTPBody = data
            }
        case .PropertyList(let (format, options)):
            if let data = NSPropertyListSerialization.dataWithPropertyList(parameters!, format: format, options: options, error: &error) {
                mutableRequest.setValue("application/x-plist", forHTTPHeaderField: "Content-Type")
                mutableRequest.HTTPBody = data
            }
        case .Custom(let closure):
            return closure(request, parameters)
        }

        return (mutableRequest, error)
    }

    private func queryComponents(key: String, _ value: AnyObject) -> [(String, String)] {
        var components: [(String, String)] = []
        if let dictionary = value as? [String: AnyObject] {
            for (nestedKey, value) in dictionary {
                components += queryComponents("\(key)[\(nestedKey)]", value)
            }
        } else if let array = value as? [AnyObject] {
            for value in array {
                components += queryComponents("\(key)[]", value)
            }
        } else {
            components.extend([(key, "\(value)")])
        }

        return components
    }
}

// MARK: - URLStringConvertible

public protocol URLStringConvertible {
    var URLString: String { get }
}

extension String: URLStringConvertible {
    public var URLString: String {
        return self
    }
}

extension NSURL: URLStringConvertible {
    public var URLString: String {
        return self.absoluteString!
    }
}

extension NSURLComponents: URLStringConvertible {
    public var URLString: String {
        return self.URL!.URLString
    }
}

extension NSURLRequest: URLStringConvertible {
    public var URLString: String {
        return self.URL.URLString
    }
}

// MARK: - URLRequestConvertible

public protocol URLRequestConvertible {
    var URLRequest: NSURLRequest { get }
}

extension NSURLRequest: URLRequestConvertible {
    public var URLRequest: NSURLRequest {
        return self
    }
}

// MARK: -

public class Manager {
    public class var sharedInstance: Manager {
        struct Singleton {
            static var configuration: NSURLSessionConfiguration = {
                var configuration = NSURLSessionConfiguration.defaultSessionConfiguration()

                configuration.HTTPAdditionalHeaders = {
                    // Accept-Encoding HTTP Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.3
                    let acceptEncoding: String = "gzip;q=1.0,compress;q=0.5"

                    // Accept-Language HTTP Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.4
                    let acceptLanguage: String = {
                        var components: [String] = []
                        for (index, languageCode) in enumerate(NSLocale.preferredLanguages() as [String]) {
                            let q = 1.0 - (Double(index) * 0.1)
                            components.append("\(languageCode);q=\(q)")
                            if q <= 0.5 {
                                break
                            }
                        }

                        return join(",", components)
                    }()

                    // User-Agent Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.43
                    let userAgent: String = {
                        let info = NSBundle.mainBundle().infoDictionary
                        let executable: AnyObject = info[kCFBundleExecutableKey] ?? "Unknown"
                        let bundle: AnyObject = info[kCFBundleIdentifierKey] ?? "Unknown"
                        let version: AnyObject = info[kCFBundleVersionKey] ?? "Unknown"
                        let os: AnyObject = NSProcessInfo.processInfo().operatingSystemVersionString ?? "Unknown"

                        var mutableUserAgent = NSMutableString(string: "\(executable)/\(bundle) (\(version); OS \(os))") as CFMutableString
                        let transform = NSString(string: "Any-Latin; Latin-ASCII; [:^ASCII:] Remove") as CFString
                        if CFStringTransform(mutableUserAgent, nil, transform, 0) == 1 {
                            return mutableUserAgent as NSString
                        }

                        return "Alamofire"
                    }()
                    
                    return ["Accept-Encoding": acceptEncoding,
                            "Accept-Language": acceptLanguage,
                            "User-Agent": userAgent]
                }()

                return configuration
            }()


            static let instance = Manager(configuration: configuration)
        }

        return Singleton.instance
    }

    let delegate: SessionDelegate
    let session: NSURLSession!
    let operationQueue: NSOperationQueue = NSOperationQueue()

    var automaticallyStartsRequests: Bool = true

    required public init(configuration: NSURLSessionConfiguration? = nil) {
        self.delegate = SessionDelegate()
        self.session = NSURLSession(configuration: configuration, delegate: self.delegate, delegateQueue: self.operationQueue)
    }

    deinit {
        self.session.invalidateAndCancel()
    }

    // MARK: -

    public func request(URLRequest: URLRequestConvertible) -> Request {
        var dataTask: NSURLSessionDataTask?
        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            dataTask = self.session.dataTaskWithRequest(URLRequest.URLRequest)
        }

        let request = Request(session: self.session, task: dataTask!)
        self.delegate[request.delegate.task] = request.delegate
        request.resume()

        return request
    }

    class SessionDelegate: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate {
        private var subdelegates: [Int: Request.TaskDelegate]
        private subscript(task: NSURLSessionTask) -> Request.TaskDelegate? {
            get {
                return self.subdelegates[task.taskIdentifier]
            }

            set {
                self.subdelegates[task.taskIdentifier] = newValue
            }
        }

        var sessionDidBecomeInvalidWithError: ((NSURLSession!, NSError!) -> Void)?
        var sessionDidFinishEventsForBackgroundURLSession: ((NSURLSession!) -> Void)?
        var sessionDidReceiveChallenge: ((NSURLSession!, NSURLAuthenticationChallenge) -> (NSURLSessionAuthChallengeDisposition, NSURLCredential!))?

        var taskWillPerformHTTPRedirection: ((NSURLSession!, NSURLSessionTask!, NSHTTPURLResponse!, NSURLRequest!) -> (NSURLRequest!))?
        var taskDidReceiveChallenge: ((NSURLSession!, NSURLSessionTask!, NSURLAuthenticationChallenge) -> (NSURLSessionAuthChallengeDisposition, NSURLCredential?))?
        var taskDidSendBodyData: ((NSURLSession!, NSURLSessionTask!, Int64, Int64, Int64) -> Void)?
        var taskNeedNewBodyStream: ((NSURLSession!, NSURLSessionTask!) -> (NSInputStream!))?

        var dataTaskDidReceiveResponse: ((NSURLSession!, NSURLSessionDataTask!, NSURLResponse!) -> (NSURLSessionResponseDisposition))?
        var dataTaskDidBecomeDownloadTask: ((NSURLSession!, NSURLSessionDataTask!) -> Void)?
        var dataTaskDidReceiveData: ((NSURLSession!, NSURLSessionDataTask!, NSData!) -> Void)?
        var dataTaskWillCacheResponse: ((NSURLSession!, NSURLSessionDataTask!, NSCachedURLResponse!) -> (NSCachedURLResponse))?

        var downloadTaskDidFinishDownloadingToURL: ((NSURLSession!, NSURLSessionDownloadTask!, NSURL) -> (NSURL))?
        var downloadTaskDidWriteData: ((NSURLSession!, NSURLSessionDownloadTask!, Int64, Int64, Int64) -> Void)?
        var downloadTaskDidResumeAtOffset: ((NSURLSession!, NSURLSessionDownloadTask!, Int64, Int64) -> Void)?

        required override init() {
            self.subdelegates = Dictionary()
            super.init()
        }

        // MARK: NSURLSessionDelegate

        func URLSession(session: NSURLSession!, didBecomeInvalidWithError error: NSError!) {
            self.sessionDidBecomeInvalidWithError?(session, error)
        }

        func URLSession(session: NSURLSession!, didReceiveChallenge challenge: NSURLAuthenticationChallenge!, completionHandler: ((NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void)!) {
            if self.sessionDidReceiveChallenge != nil {
                completionHandler(self.sessionDidReceiveChallenge!(session, challenge))
            } else {
                completionHandler(.PerformDefaultHandling, nil)
            }
        }

        func URLSessionDidFinishEventsForBackgroundURLSession(session: NSURLSession!) {
            self.sessionDidFinishEventsForBackgroundURLSession?(session)
        }

        // MARK: NSURLSessionTaskDelegate

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, willPerformHTTPRedirection response: NSHTTPURLResponse!, newRequest request: NSURLRequest!, completionHandler: ((NSURLRequest!) -> Void)!) {
            var redirectRequest = request
            if self.taskWillPerformHTTPRedirection != nil {
                redirectRequest = self.taskWillPerformHTTPRedirection!(session, task, response, request)
            }

            completionHandler(redirectRequest)
        }

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, didReceiveChallenge challenge: NSURLAuthenticationChallenge!, completionHandler: ((NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void)!) {
            if let delegate = self[task] {
                delegate.URLSession(session, task: task, didReceiveChallenge: challenge, completionHandler: completionHandler)
            } else {
                self.URLSession(session, didReceiveChallenge: challenge, completionHandler: completionHandler)
            }
        }

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, needNewBodyStream completionHandler: ((NSInputStream!) -> Void)!) {
            if let delegate = self[task] {
                delegate.URLSession(session, task: task, needNewBodyStream: completionHandler)
            }
        }

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            if let delegate = self[task] as? Request.UploadTaskDelegate {
                delegate.URLSession(session, task: task, didSendBodyData: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
            }
        }

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, didCompleteWithError error: NSError!) {
            if let delegate = self[task] {
                delegate.URLSession(session, task: task, didCompleteWithError: error)

                self[task] = nil
            }
        }

        // MARK: NSURLSessionDataDelegate

        func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!, didReceiveResponse response: NSURLResponse!, completionHandler: ((NSURLSessionResponseDisposition) -> Void)!) {
            var disposition: NSURLSessionResponseDisposition = .Allow

            if self.dataTaskDidReceiveResponse != nil {
                disposition = self.dataTaskDidReceiveResponse!(session, dataTask, response)
            }

            completionHandler(disposition)
        }

        func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!, didBecomeDownloadTask downloadTask: NSURLSessionDownloadTask!) {
            let downloadDelegate = Request.DownloadTaskDelegate(task: downloadTask)
            self[downloadTask] = downloadDelegate
        }

        func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!, didReceiveData data: NSData!) {
            if let delegate = self[dataTask] as? Request.DataTaskDelegate {
                delegate.URLSession(session, dataTask: dataTask, didReceiveData: data)
            }

            self.dataTaskDidReceiveData?(session, dataTask, data)
        }

        func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!, willCacheResponse proposedResponse: NSCachedURLResponse!, completionHandler: ((NSCachedURLResponse!) -> Void)!) {
            var cachedResponse = proposedResponse

            if self.dataTaskWillCacheResponse != nil {
                cachedResponse = self.dataTaskWillCacheResponse!(session, dataTask, proposedResponse)
            }

            completionHandler(cachedResponse)
        }

        // MARK: NSURLSessionDownloadDelegate

        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
            if let delegate = self[downloadTask] as? Request.DownloadTaskDelegate {
                delegate.URLSession(session, downloadTask: downloadTask, didFinishDownloadingToURL: location)
            }

            self.downloadTaskDidFinishDownloadingToURL?(session, downloadTask, location)
        }

        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if let delegate = self[downloadTask] as? Request.DownloadTaskDelegate {
                delegate.URLSession(session, downloadTask: downloadTask, didWriteData: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
            }

            self.downloadTaskDidWriteData?(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
        }

        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
            if let delegate = self[downloadTask] as? Request.DownloadTaskDelegate {
                delegate.URLSession(session, downloadTask: downloadTask, didResumeAtOffset: fileOffset, expectedTotalBytes: expectedTotalBytes)
            }

            self.downloadTaskDidResumeAtOffset?(session, downloadTask, fileOffset, expectedTotalBytes)
        }

        // MARK: NSObject

        override func respondsToSelector(selector: Selector) -> Bool {
            switch selector {
            case "URLSession:didBecomeInvalidWithError:":
                return (self.sessionDidBecomeInvalidWithError != nil)
            case "URLSession:didReceiveChallenge:completionHandler:":
                return (self.sessionDidReceiveChallenge != nil)
            case "URLSessionDidFinishEventsForBackgroundURLSession:":
                return (self.sessionDidFinishEventsForBackgroundURLSession != nil)
            case "URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:":
                return (self.taskWillPerformHTTPRedirection != nil)
            case "URLSession:dataTask:didReceiveResponse:completionHandler:":
                return (self.dataTaskDidReceiveResponse != nil)
            case "URLSession:dataTask:willCacheResponse:completionHandler:":
                return (self.dataTaskWillCacheResponse != nil)
            default:
                return self.dynamicType.instancesRespondToSelector(selector)
            }
        }
    }
}

// MARK: -

public class Request {
    private let delegate: TaskDelegate

    private var session: NSURLSession
    private var task: NSURLSessionTask { return self.delegate.task }

    public var request: NSURLRequest { return self.task.originalRequest }
    public var response: NSHTTPURLResponse? { return self.task.response as? NSHTTPURLResponse }
    public var progress: NSProgress? { return self.delegate.progress }

    private init(session: NSURLSession, task: NSURLSessionTask) {
        self.session = session

        switch task {
        case is NSURLSessionUploadTask:
            self.delegate = UploadTaskDelegate(task: task)
        case is NSURLSessionDataTask:
            self.delegate = DataTaskDelegate(task: task)
        case is NSURLSessionDownloadTask:
            self.delegate = DownloadTaskDelegate(task: task)
        default:
            self.delegate = TaskDelegate(task: task)
        }
    }

    // MARK: Authentication

    public func authenticate(#user: String, password: String) -> Self {
        let credential = NSURLCredential(user: user, password: password, persistence: .ForSession)

        return authenticate(usingCredential: credential)
    }

    public func authenticate(usingCredential credential: NSURLCredential) -> Self {
        self.delegate.credential = credential

        return self
    }

    // MARK: Progress

    public func progress(closure: ((Int64, Int64, Int64) -> Void)? = nil) -> Self {
        if let uploadDelegate = self.delegate as? UploadTaskDelegate {
            uploadDelegate.uploadProgress = closure
        } else if let downloadDelegate = self.delegate as? DownloadTaskDelegate {
            downloadDelegate.downloadProgress = closure
        } else if let dataDelegate = self.delegate as? DataTaskDelegate {
            dataDelegate.dataProgress = closure
        }

        return self
    }

    // MARK: Response

    public typealias Serializer = (NSURLRequest, NSHTTPURLResponse?, NSData?) -> (AnyObject?, NSError?)

    public class func responseDataSerializer() -> Serializer {
        return { (request, response, data) in
            return (data, nil)
        }
    }

    public func response(completionHandler: (NSURLRequest, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void) -> Self {
        return response(Request.responseDataSerializer(), completionHandler: completionHandler)
    }

    public func response(priority: Int = DISPATCH_QUEUE_PRIORITY_DEFAULT, queue: dispatch_queue_t? = nil, serializer: Serializer, completionHandler: (NSURLRequest, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void) -> Self {

        dispatch_async(self.delegate.queue, {
            dispatch_async(dispatch_get_global_queue(priority, 0), {
                if var error = self.delegate.error {
                    dispatch_async(queue ?? dispatch_get_main_queue(), {
                        completionHandler(self.request, self.response, nil, error)
                    })
                } else {
                    let (responseObject: AnyObject?, serializationError: NSError?) = serializer(self.request, self.response, self.delegate.data)

                    dispatch_async(queue ?? dispatch_get_main_queue(), {
                        completionHandler(self.request, self.response, responseObject, serializationError)
                    })
                }
            })
        })

        return self
    }

    public func suspend() {
        self.task.suspend()
    }

    public func resume() {
        self.task.resume()
    }

    public func cancel() {
        if let downloadDelegate = self.delegate as? DownloadTaskDelegate {
            downloadDelegate.downloadTask.cancelByProducingResumeData { (data) in
                downloadDelegate.resumeData = data
            }
        } else {
            self.task.cancel()
        }
    }

    private class TaskDelegate: NSObject, NSURLSessionTaskDelegate {
        let task: NSURLSessionTask
        let queue: dispatch_queue_t?
        let progress: NSProgress

        var data: NSData? { return nil }
        private(set) var error: NSError?

        var credential: NSURLCredential?

        var taskWillPerformHTTPRedirection: ((NSURLSession!, NSURLSessionTask!, NSHTTPURLResponse!, NSURLRequest!) -> (NSURLRequest!))?
        var taskDidReceiveChallenge: ((NSURLSession!, NSURLSessionTask!, NSURLAuthenticationChallenge) -> (NSURLSessionAuthChallengeDisposition, NSURLCredential?))?
        var taskDidSendBodyData: ((NSURLSession!, NSURLSessionTask!, Int64, Int64, Int64) -> Void)?
        var taskNeedNewBodyStream: ((NSURLSession!, NSURLSessionTask!) -> (NSInputStream!))?

        init(task: NSURLSessionTask) {
            self.task = task
            self.progress = NSProgress(totalUnitCount: 0)

            let label: String = "com.alamofire.task-\(task.taskIdentifier)"
            let queue = dispatch_queue_create((label as NSString).UTF8String, DISPATCH_QUEUE_SERIAL)
            dispatch_suspend(queue)
            self.queue = queue
        }

        // MARK: NSURLSessionTaskDelegate

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, willPerformHTTPRedirection response: NSHTTPURLResponse!, newRequest request: NSURLRequest!, completionHandler: ((NSURLRequest!) -> Void)!) {
            var redirectRequest = request
            if self.taskWillPerformHTTPRedirection != nil {
                redirectRequest = self.taskWillPerformHTTPRedirection!(session, task, response, request)
            }

            completionHandler(redirectRequest)
        }

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, didReceiveChallenge challenge: NSURLAuthenticationChallenge!, completionHandler: ((NSURLSessionAuthChallengeDisposition, NSURLCredential!) -> Void)!) {
            var disposition: NSURLSessionAuthChallengeDisposition = .PerformDefaultHandling
            var credential: NSURLCredential?

            if self.taskDidReceiveChallenge != nil {
                (disposition, credential) = self.taskDidReceiveChallenge!(session, task, challenge)
            } else {
                if challenge.previousFailureCount > 0 {
                    disposition = .CancelAuthenticationChallenge
                } else {
                    // TODO: Incorporate Trust Evaluation & TLS Chain Validation

                    switch challenge.protectionSpace.authenticationMethod! {
                    case NSURLAuthenticationMethodServerTrust:
                        credential = NSURLCredential(forTrust: challenge.protectionSpace.serverTrust)
                    default:
                        credential = self.credential ?? session.configuration.URLCredentialStorage?.defaultCredentialForProtectionSpace(challenge.protectionSpace)
                    }

                    if credential != nil {
                        disposition = .UseCredential
                    }
                }
            }

            completionHandler(disposition, credential)
        }

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, needNewBodyStream completionHandler: ((NSInputStream!) -> Void)!) {
            var bodyStream: NSInputStream?
            if self.taskNeedNewBodyStream != nil {
                bodyStream = self.taskNeedNewBodyStream!(session, task)
            }

            completionHandler(bodyStream)
        }

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, didCompleteWithError error: NSError!) {
            self.error = error
            dispatch_resume(self.queue)
        }
    }

    private class DataTaskDelegate: TaskDelegate, NSURLSessionDataDelegate {
        var dataTask: NSURLSessionDataTask! { return self.task as NSURLSessionDataTask }

        private var mutableData: NSMutableData
        override var data: NSData? {
            return self.mutableData
        }

        private var expectedContentLength: Int64?

        var dataTaskDidReceiveResponse: ((NSURLSession!, NSURLSessionDataTask!, NSURLResponse!) -> (NSURLSessionResponseDisposition))?
        var dataTaskDidBecomeDownloadTask: ((NSURLSession!, NSURLSessionDataTask!) -> Void)?
        var dataTaskDidReceiveData: ((NSURLSession!, NSURLSessionDataTask!, NSData!) -> Void)?
        var dataTaskWillCacheResponse: ((NSURLSession!, NSURLSessionDataTask!, NSCachedURLResponse!) -> (NSCachedURLResponse))?
        var dataProgress: ((bytesReceived: Int64, totalBytesReceived: Int64, totalBytesExpectedToReceive: Int64) -> Void)?

        override init(task: NSURLSessionTask) {
            self.mutableData = NSMutableData()
            super.init(task: task)
        }

        // MARK: NSURLSessionDataDelegate

        func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!, didReceiveResponse response: NSURLResponse!, completionHandler: ((NSURLSessionResponseDisposition) -> Void)!) {
            var disposition: NSURLSessionResponseDisposition = .Allow

            expectedContentLength = response.expectedContentLength

            if self.dataTaskDidReceiveResponse != nil {
                disposition = self.dataTaskDidReceiveResponse!(session, dataTask, response)
            }

            completionHandler(disposition)
        }

        func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!, didBecomeDownloadTask downloadTask: NSURLSessionDownloadTask!) {
            self.dataTaskDidBecomeDownloadTask?(session, dataTask)
        }

        func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!, didReceiveData data: NSData!) {
            self.dataTaskDidReceiveData?(session, dataTask, data)

            self.mutableData.appendData(data)

            if let expectedContentLength = dataTask?.response?.expectedContentLength {
                self.dataProgress?(bytesReceived: Int64(data.length), totalBytesReceived: Int64(self.mutableData.length), totalBytesExpectedToReceive: expectedContentLength)
            }
        }

        func URLSession(session: NSURLSession!, dataTask: NSURLSessionDataTask!, willCacheResponse proposedResponse: NSCachedURLResponse!, completionHandler: ((NSCachedURLResponse!) -> Void)!) {
            var cachedResponse = proposedResponse

            if self.dataTaskWillCacheResponse != nil {
                cachedResponse = self.dataTaskWillCacheResponse!(session, dataTask, proposedResponse)
            }

            completionHandler(cachedResponse)
        }
    }
}


// MARK: - Upload

extension Manager {
    private enum Uploadable {
        case Data(NSURLRequest, NSData)
        case File(NSURLRequest, NSURL)
        case Stream(NSURLRequest, NSInputStream)
    }

    private func upload(uploadable: Uploadable) -> Request {
        var uploadTask: NSURLSessionUploadTask!
        var stream: NSInputStream?

        switch uploadable {
        case .Data(let request, let data):
            uploadTask = self.session.uploadTaskWithRequest(request, fromData: data)
        case .File(let request, let fileURL):
            uploadTask = self.session.uploadTaskWithRequest(request, fromFile: fileURL)
        case .Stream(let request, var stream):
            uploadTask = self.session.uploadTaskWithStreamedRequest(request)
        }

        let request = Request(session: self.session, task: uploadTask)
        if stream != nil {
            request.delegate.taskNeedNewBodyStream = { _, _ in
                return stream
            }
        }
        self.delegate[request.delegate.task] = request.delegate

        if self.automaticallyStartsRequests {
            request.resume()
        }

        return request
    }

    // MARK: File

    func upload(request: NSURLRequest, file: NSURL) -> Request {
        return upload(.File(request, file))
    }

    // MARK: Data

    func upload(request: NSURLRequest, data: NSData) -> Request {
        return upload(.Data(request, data))
    }

    // MARK: Stream

    func upload(request: NSURLRequest, stream: NSInputStream) -> Request {
        return upload(.Stream(request, stream))
    }
}

extension Request {
    private class UploadTaskDelegate: DataTaskDelegate {
        var uploadTask: NSURLSessionUploadTask! { return self.task as NSURLSessionUploadTask }
        var uploadProgress: ((Int64, Int64, Int64) -> Void)!

        // MARK: NSURLSessionTaskDelegate

        func URLSession(session: NSURLSession!, task: NSURLSessionTask!, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            if self.uploadProgress != nil {
                self.uploadProgress(bytesSent, totalBytesSent, totalBytesExpectedToSend)
            }

            self.progress.totalUnitCount = totalBytesExpectedToSend
            self.progress.completedUnitCount = totalBytesSent
        }
    }
}

// MARK: - Download

extension Manager {
    private enum Downloadable {
        case Request(NSURLRequest)
        case ResumeData(NSData)
    }

    private func download(downloadable: Downloadable, destination: (NSURL, NSHTTPURLResponse) -> (NSURL)) -> Request {
        var downloadTask: NSURLSessionDownloadTask!

        switch downloadable {
        case .Request(let request):
            downloadTask = self.session.downloadTaskWithRequest(request)
        case .ResumeData(let resumeData):
            downloadTask = self.session.downloadTaskWithResumeData(resumeData)
        }

        let request = Request(session: self.session, task: downloadTask)
        if let downloadDelegate = request.delegate as? Request.DownloadTaskDelegate {
            downloadDelegate.downloadTaskDidFinishDownloadingToURL = { (session, downloadTask, URL) in
                return destination(URL, downloadTask.response as NSHTTPURLResponse)
            }
        }
        self.delegate[request.delegate.task] = request.delegate

        if self.automaticallyStartsRequests {
            request.resume()
        }

        return request
    }

    // MARK: Request

    public func download(request: NSURLRequest, destination: (NSURL, NSHTTPURLResponse) -> (NSURL)) -> Request {
        return download(.Request(request), destination: destination)
    }

    // MARK: Resume Data

    public func download(resumeData: NSData, destination: (NSURL, NSHTTPURLResponse) -> (NSURL)) -> Request {
        return download(.ResumeData(resumeData), destination: destination)
    }
}

extension Request {
    public class func suggestedDownloadDestination(directory: NSSearchPathDirectory = .DocumentDirectory, domain: NSSearchPathDomainMask = .UserDomainMask) -> (NSURL, NSHTTPURLResponse) -> (NSURL) {

        return { (temporaryURL, response) -> (NSURL) in
            if let directoryURL = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)[0] as? NSURL {
                return directoryURL.URLByAppendingPathComponent(response.suggestedFilename!)
            }

            return temporaryURL
        }
    }

    private class DownloadTaskDelegate: TaskDelegate, NSURLSessionDownloadDelegate {
        var downloadTask: NSURLSessionDownloadTask! { return self.task as NSURLSessionDownloadTask }
        var downloadProgress: ((Int64, Int64, Int64) -> Void)?

        var resumeData: NSData?
        override var data: NSData? { return self.resumeData }

        var downloadTaskDidFinishDownloadingToURL: ((NSURLSession!, NSURLSessionDownloadTask!, NSURL) -> (NSURL))?
        var downloadTaskDidWriteData: ((NSURLSession!, NSURLSessionDownloadTask!, Int64, Int64, Int64) -> Void)?
        var downloadTaskDidResumeAtOffset: ((NSURLSession!, NSURLSessionDownloadTask!, Int64, Int64) -> Void)?

        // MARK: NSURLSessionDownloadDelegate

        func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
            if self.downloadTaskDidFinishDownloadingToURL != nil {
                let destination = self.downloadTaskDidFinishDownloadingToURL!(session, downloadTask, location)
                var fileManagerError: NSError?

                NSFileManager.defaultManager().moveItemAtURL(location, toURL: destination, error: &fileManagerError)
                if fileManagerError != nil {
                    self.error = fileManagerError
                }
            }
        }

        func URLSession(session: NSURLSession!, downloadTask: NSURLSessionDownloadTask!, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            self.downloadTaskDidWriteData?(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)

            self.downloadProgress?(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)

            self.progress.totalUnitCount = totalBytesExpectedToWrite
            self.progress.completedUnitCount = totalBytesWritten
        }

        func URLSession(session: NSURLSession!, downloadTask: NSURLSessionDownloadTask!, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
            self.downloadTaskDidResumeAtOffset?(session, downloadTask, fileOffset, expectedTotalBytes)

            self.progress.totalUnitCount = expectedTotalBytes
            self.progress.completedUnitCount = fileOffset
        }
    }
}

// MARK: - Printable

extension Request: Printable {
    public var description: String {
        var components: [String] = []
        if self.request.HTTPMethod != nil {
            components.append(self.request.HTTPMethod!)
        }

        components.append(self.request.URL.absoluteString!)

        if self.response != nil {
            components.append("(\(self.response!.statusCode))")
        }

        return join(" ", components)
    }
}

extension Request: DebugPrintable {
    func cURLRepresentation() -> String {
        var components: [String] = ["$ curl -i"]

        let URL = self.request.URL

        if self.request.HTTPMethod != nil && self.request.HTTPMethod != "GET" {
            components.append("-X \(self.request.HTTPMethod!)")
        }

        if let credentialStorage = self.session.configuration.URLCredentialStorage {
            let protectionSpace = NSURLProtectionSpace(host: URL.host!, port: URL.port ?? 0, `protocol`: URL.scheme, realm: URL.host, authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            if let credentials = credentialStorage.credentialsForProtectionSpace(protectionSpace)?.values.array {
                for credential: NSURLCredential in (credentials as [NSURLCredential]) {
                    components.append("-u \(credential.user):\(credential.password)")
                }
            } else {
                if let credential = self.delegate.credential {
                    components.append("-u \(credential.user):\(credential.password)")
                }
            }
        }

        if let cookieStorage = self.session.configuration.HTTPCookieStorage {
            if let cookies = cookieStorage.cookiesForURL(URL) as? [NSHTTPCookie] {
                if !cookies.isEmpty {
                    let string = cookies.reduce(""){ $0 + "\($1.name)=\($1.value);" }
                    components.append("-b \"\(string.substringToIndex(string.endIndex.predecessor()))\"")
                }
            }
        }

        for (field, value) in self.request.allHTTPHeaderFields! {
            switch field {
            case "Cookie":
                continue
            default:
                components.append("-H \"\(field): \(value)\"")
            }
        }

        if let HTTPBody = self.request.HTTPBody {
            components.append("-d \"\(NSString(data: HTTPBody, encoding: NSUTF8StringEncoding))\"")
        }

        components.append("\"\(URL.absoluteString!)\"")

        return join(" \\\n\t", components)
    }

    public var debugDescription: String {
        return self.cURLRepresentation()
    }
}

// MARK: - Response Serializers

// MARK: String

extension Request {
    public class func stringResponseSerializer(encoding: NSStringEncoding = NSUTF8StringEncoding) -> Serializer {
        return { (_, _, data) in
            let string = NSString(data: data!, encoding: encoding)

            return (string, nil)
        }
    }

    public func responseString(completionHandler: (NSURLRequest, NSHTTPURLResponse?, String?, NSError?) -> Void) -> Self {
        return responseString(completionHandler: completionHandler)
    }

    public func responseString(encoding: NSStringEncoding = NSUTF8StringEncoding, completionHandler: (NSURLRequest, NSHTTPURLResponse?, String?, NSError?) -> Void) -> Self  {
        return response(serializer: Request.stringResponseSerializer(encoding: encoding), completionHandler: { request, response, string, error in
            completionHandler(request, response, string as? String, error)
        })
    }
}

// MARK: JSON

extension Request {
    public class func JSONResponseSerializer(options: NSJSONReadingOptions = .AllowFragments) -> Serializer {
        return { (request, response, data) in
            var serializationError: NSError?
            let JSON: AnyObject? = NSJSONSerialization.JSONObjectWithData(data!, options: options, error: &serializationError)

            return (JSON, serializationError)
        }
    }

    public func responseJSON(completionHandler: (NSURLRequest, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void) -> Self {
        return responseJSON(completionHandler: completionHandler)
    }

    public func responseJSON(options: NSJSONReadingOptions = .AllowFragments, completionHandler: (NSURLRequest, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void) -> Self {
        return response(serializer: Request.JSONResponseSerializer(options: options), completionHandler: { (request, response, JSON, error) in
            completionHandler(request, response, JSON, error)
        })
    }
}

// MARK: Property List

extension Request {
    public class func propertyListResponseSerializer(options: NSPropertyListReadOptions = 0) -> Serializer {
        return { (request, response, data) in
            var propertyListSerializationError: NSError?
            let plist: AnyObject? = NSPropertyListSerialization.propertyListWithData(data!, options: options, format: nil, error: &propertyListSerializationError)

            return (plist, propertyListSerializationError)
        }
    }

    public func responsePropertyList(completionHandler: (NSURLRequest, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void) -> Self {
        return responsePropertyList(completionHandler: completionHandler)
    }

    public func responsePropertyList(options: NSPropertyListReadOptions = 0, completionHandler: (NSURLRequest, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void) -> Self {
        return response(serializer: Request.propertyListResponseSerializer(options: options), completionHandler: { (request, response, plist, error) in
            completionHandler(request, response, plist, error)
        })
    }
}

// MARK: - Convenience

private func URLRequest(method: Method, URLString: URLStringConvertible) -> NSURLRequest {
    let mutableURLRequest = NSMutableURLRequest(URL: NSURL(string: URLString.URLString))
    mutableURLRequest.HTTPMethod = method.toRaw()

    return mutableURLRequest
}

// MARK: Request

public func request(method: Method, URLString: URLStringConvertible, parameters: [String: AnyObject]? = nil, encoding: ParameterEncoding = .URL) -> Request {
    return request(encoding.encode(URLRequest(method, URLString), parameters: parameters).0)
}

public func request(URLRequest: URLRequestConvertible) -> Request {
    return Manager.sharedInstance.request(URLRequest.URLRequest)
}

// MARK: Upload

public func upload(method: Method, URLString: URLStringConvertible, file: NSURL) -> Request {
    return Manager.sharedInstance.upload(URLRequest(method, URLString), file: file)
}

public func upload(method: Method, URLString: URLStringConvertible, data: NSData) -> Request {
    return Manager.sharedInstance.upload(URLRequest(method, URLString), data: data)
}

public func upload(method: Method, URLString: URLStringConvertible, stream: NSInputStream) -> Request {
    return Manager.sharedInstance.upload(URLRequest(method, URLString), stream: stream)
}

// MARK: Download

public func download(method: Method, URLString: URLStringConvertible, destination: (NSURL, NSHTTPURLResponse) -> (NSURL)) -> Request {
    return Manager.sharedInstance.download(URLRequest(method, URLString), destination: destination)
}

public func download(resumeData data: NSData, destination: (NSURL, NSHTTPURLResponse) -> (NSURL)) -> Request {
    return Manager.sharedInstance.download(data, destination: destination)
}
