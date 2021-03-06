//
//  RoomListener.swift
//  Hakumai
//
//  Created by Hiroyuki Onishi on 11/16/14.
//  Copyright (c) 2014 Hiroyuki Onishi. All rights reserved.
//

import Foundation
import XCGLogger

private let kFileLogNamePrefix = "Hakumai_"
private let kFileLogNameSuffix = ".log"

private let kReadBufferSize = 102400
private let kPingInterval: TimeInterval = 60

// MARK: protocol

protocol RoomListenerDelegate: class {
    func roomListenerDidReceiveThread(_ roomListener: RoomListener, thread: Thread)
    func roomListenerDidReceiveChat(_ roomListener: RoomListener, chat: Chat)
    func roomListenerDidFinishListening(_ roomListener: RoomListener)
}

// MARK: main

class RoomListener : NSObject, StreamDelegate {
    weak var delegate: RoomListenerDelegate?
    let server: MessageServer?
    
    private var runLoop: RunLoop!
    
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var pingTimer: Timer?
    
    private var parsingString: String = ""
    
    private var thread: Thread?
    private var startDate: Date?
    private(set) var lastRes: Int = 0
    private var internalNo: Int = 0
    
    private let fileLogger = XCGLogger()
    
    init(delegate: RoomListenerDelegate?, server: MessageServer?) {
        self.delegate = delegate
        self.server = server
        
        super.init()
        
        initializeFileLogger()
        logger.info("listener initialized for message server:\(self.server)")
    }
    
    deinit {
        logger.debug("")
    }
    
    private func initializeFileLogger() {
        var logNumber = 0
        if let server = server {
            logNumber = server.roomPosition.rawValue
        }
        
        let fileName = kFileLogNamePrefix + String(logNumber) + kFileLogNameSuffix
        Helper.setupFileLogger(fileLogger, fileName: fileName)
    }
    
    // MARK: - Public Functions
    func openSocket(resFrom: Int = 0) {
        guard let server = server else {
            return
        }
        
        var input :InputStream?
        var output :OutputStream?
        
        Stream.getStreamsToHost(withName: server.address, port: server.port, inputStream: &input, outputStream: &output)
        
        if input == nil || output == nil {
            fileLogger.error("failed to open socket.")
            return
        }
        
        inputStream = input
        outputStream = output
        
        inputStream?.delegate = self
        outputStream?.delegate = self
        
        runLoop = RunLoop.current
        
        inputStream?.schedule(in: runLoop, forMode: RunLoopMode.defaultRunLoopMode)
        outputStream?.schedule(in: runLoop, forMode: RunLoopMode.defaultRunLoopMode)
        
        inputStream?.open()
        outputStream?.open()
        
        let message = "<thread thread=\"\(server.thread)\" res_from=\"-\(resFrom)\" version=\"20061206\"/>"
        send(message: message)
        
        startPingTimer()

        while inputStream != nil {
            runLoop.run(until: Date(timeIntervalSinceNow: TimeInterval(1)))
        }
        
        delegate?.roomListenerDidFinishListening(self)
    }
    
    func closeSocket() {
        fileLogger.debug("closed streams.")
        
        stopPingTimer()

        inputStream?.delegate = nil
        outputStream?.delegate = nil
        
        inputStream?.close()
        outputStream?.close()
        
        inputStream?.remove(from: runLoop, forMode: RunLoopMode.defaultRunLoopMode)
        outputStream?.remove(from: runLoop, forMode: RunLoopMode.defaultRunLoopMode)
        
        inputStream = nil
        outputStream = nil
    }
    
    func comment(live: Live, user: User, postKey: String, comment: String, anonymously: Bool) {
        guard let thread = thread else {
            logger.debug("could not get thread information")
            return
        }
        
        let threadNumber = thread.thread!
        let ticket = thread.ticket!
        let originTime = Int(thread.serverTime!.timeIntervalSince1970) - Int(live.baseTime!.timeIntervalSince1970)
        let elapsedTime = Int(Date().timeIntervalSince1970) - Int(startDate!.timeIntervalSince1970)
        let vpos = (originTime + elapsedTime) * 100
        let mail = anonymously ? "184" : ""
        let userId = user.userId!
        let premium = user.isPremium!
        
        let message = "<chat thread=\"\(threadNumber)\" ticket=\"\(ticket)\" vpos=\"\(vpos)\" postkey=\"\(postKey)\" mail=\"\(mail)\" user_id=\"\(userId)\" premium=\"\(premium)\">\(comment)</chat>"
        
        send(message: message)
    }
    
    private func send(message: String, logging: Bool = true) {
        let data: Data = (message + "\0").data(using: String.Encoding.utf8)!
        outputStream?.write(unsafeBitCast((data as NSData).bytes, to: UnsafePointer<UInt8>.self), maxLength: data.count)
 
        if logging {
            logger.debug(message)
        }
    }
    
    // MARK: - NSStreamDelegate Functions
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event():
            fileLogger.debug("stream event none")
            
        case Stream.Event.openCompleted:
            fileLogger.debug("stream event open completed")
            
        case Stream.Event.hasBytesAvailable:
            // fileLogger.debug("stream event has bytes available")
            
            // http://stackoverflow.com/q/26360962
            var readByte = [UInt8](repeating: 0, count: kReadBufferSize)
            
            var actualRead = 0
            while inputStream?.hasBytesAvailable == true {
                actualRead = inputStream!.read(&readByte, maxLength: kReadBufferSize)
                //fileLogger.debug(readByte)
                
                if let readString = NSString(bytes: &readByte, length: actualRead, encoding: String.Encoding.utf8.rawValue) {
                    fileLogger.debug("read: [ \(readString) ]")
                    
                    parsingString += streamByRemovingNull(fromStream: readString as String)
                    
                    if !hasValidCloseBracket(inStream: parsingString) {
                        fileLogger.warning("detected no-close-bracket stream, continue reading...")
                        continue
                    }
                    
                    if !hasValidOpenBracket(inStream: parsingString) {
                        fileLogger.warning("detected no-open-bracket stream, clearing buffer and continue reading...")
                        parsingString = ""
                        continue
                    }
                    
                    parseInputStream(parsingString)
                    parsingString = ""
                }
            }
            
            
        case Stream.Event.hasSpaceAvailable:
            fileLogger.debug("stream event has space available")
            
        case Stream.Event.errorOccurred:
            fileLogger.error("stream event error occurred")
            closeSocket()
            
        case Stream.Event.endEncountered:
            fileLogger.debug("stream event end encountered")
            
        default:
            fileLogger.warning("unexpected stream event")
        }
    }

    // MARK: Read Utility
    func streamByRemovingNull(fromStream stream: String) -> String {
        let regexp = try! NSRegularExpression(pattern: "\0", options: [])
        let removed = regexp.stringByReplacingMatches(in: stream, options: [], range: NSMakeRange(0, stream.utf16.count), withTemplate: "")
        
        return removed
    }
    
    func hasValidOpenBracket(inStream stream: String) -> Bool {
        return hasValid(pattern: "^<", inStream: stream)
    }
    
    func hasValidCloseBracket(inStream stream: String) -> Bool {
        return hasValid(pattern: ">$", inStream: stream)
    }
    
    private func hasValid(pattern: String, inStream stream: String) -> Bool {
        let regexp = try! NSRegularExpression(pattern: pattern, options: [])
        let matched = regexp.firstMatch(in: stream, options: [], range: NSMakeRange(0, stream.utf16.count))
        
        return matched != nil
    }
    
    // MARK: - Parse Utility
    private func parseInputStream(_ stream: String) {
        let wrappedStream = "<items>" + stream + "</items>"
        fileLogger.verbose("parsing: [ \(wrappedStream) ]")
        
        var err: NSError?
        let xmlDocument: XMLDocument?
        do {
            // NSXMLDocumentTidyXML
            xmlDocument = try XMLDocument(xmlString: wrappedStream, options: Int(UInt(XMLDocument.ContentKind.xml.rawValue)))
        } catch let error as NSError {
            err = error
            logger.error("\(err)")
            xmlDocument = nil
        }
        
        if xmlDocument == nil {
            fileLogger.error("could not parse input stream:\(stream)")
            return
        }
        
        if let rootElement = xmlDocument?.rootElement() {
            // rootElement = '<items>...</item>'

            let threads = parseThreadElement(rootElement)
            for _thread in threads {
                thread = _thread
                lastRes = _thread.lastRes!
                startDate = Date()
                delegate?.roomListenerDidReceiveThread(self, thread: _thread)
            }
        
            let chats = parseChatElement(rootElement)
            for chat in chats {
                if let chatNo = chat.no {
                    lastRes = chatNo
                }
                
                delegate?.roomListenerDidReceiveChat(self, chat: chat)
            }
            
            let chatResults = parseChatResultElement(rootElement)
            for chatResult in chatResults {
                logger.debug("\(chatResult.description)")
            }
        }
    }
    
    func parseThreadElement(_ rootElement: XMLElement) -> [Thread] {
        var threads = [Thread]()
        let threadElements = rootElement.elements(forName: "thread")
        
        for threadElement in threadElements {
            let thread = Thread()

            if let rc = threadElement.attribute(forName: "resultcode")?.stringValue, let intrc = Int(rc) {
                thread.resultCode = intrc
            }

            if let th = threadElement.attribute(forName: "thread")?.stringValue, let intth = Int(th) {
                thread.thread = intth
            }

            if let lr = threadElement.attribute(forName: "last_res")?.stringValue, let intlr = Int(lr) {
                thread.lastRes = intlr
            }
            else {
                thread.lastRes = 0
            }
            
            thread.ticket = threadElement.attribute(forName: "ticket")?.stringValue

            if let st = threadElement.attribute(forName: "server_time")?.stringValue, let intst = Int(st) {
                thread.serverTime = intst.toDateAsTimeIntervalSince1970()
            }

            threads.append(thread)
        }
        
        return threads
    }
    
    func parseChatElement(_ rootElement: XMLElement) -> [Chat] {
        var chats = [Chat]()
        let chatElements = rootElement.elements(forName: "chat")
        
        for chatElement in chatElements {
            let chat = Chat()

            chat.internalNo = internalNo
            internalNo += 1
            chat.roomPosition = server?.roomPosition
            
            if let pr = chatElement.attribute(forName: "premium")?.stringValue, let intpr = Int(pr) {
                chat.premium = Premium(rawValue: intpr)
            }
            else {
                // assume no attribute provided as Ippan(0)
                chat.premium = Premium(rawValue: 0)
            }
            
            if let sc = chatElement.attribute(forName: "score")?.stringValue, let intsc = Int(sc) {
                chat.score = intsc
            }
            else {
                chat.score = 0
            }

            if let no = chatElement.attribute(forName: "no")?.stringValue, let intno = Int(no) {
                chat.no = intno
            }

            if let dt = chatElement.attribute(forName: "date")?.stringValue, let intdt = Int(dt) {
                chat.date = intdt.toDateAsTimeIntervalSince1970()
            }

            if let du = chatElement.attribute(forName: "date_usec")?.stringValue, let intdu = Int(du) {
                chat.dateUsec = intdu
            }

            if let separated = chatElement.attribute(forName: "mail")?.stringValue?.components(separatedBy: " ") {
                chat.mail = separated
            }

            chat.userId = chatElement.attribute(forName: "user_id")?.stringValue
            chat.comment = chatElement.stringValue
            
            if chat.no == nil || chat.userId == nil || chat.comment == nil {
                logger.warning("skipped invalid chat:[\(chat)]")
                continue
            }
            
            chats.append(chat)
        }
        
        return chats
    }
    
    private func parseChatResultElement(_ rootElement: XMLElement) -> [ChatResult] {
        var chatResults = [ChatResult]()
        let chatResultElements = rootElement.elements(forName: "chat_result")
        
        for chatResultElement in chatResultElements {
            let chatResult = ChatResult()
            
            if let st = chatResultElement.attribute(forName: "status")?.stringValue, let intst = Int(st) {
                chatResult.status = ChatResult.Status(rawValue: intst)
            }
            
            chatResults.append(chatResult)
        }
        
        return chatResults
    }

    // MARK: - Private Functions
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(
            timeInterval: kPingInterval, target: self, selector: #selector(RoomListener.sendPing(_:)), userInfo: nil, repeats: true)
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    func sendPing(_ timer: Timer) {
        send(message: "<ping>PING</ping>", logging: false)
    }
}
