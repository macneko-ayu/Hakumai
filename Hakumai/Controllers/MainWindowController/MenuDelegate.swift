//
//  MenuDelegate.swift
//  Hakumai
//
//  Created by Hiroyuki Onishi on 12/4/14.
//  Copyright (c) 2014 Hiroyuki Onishi. All rights reserved.
//

import Foundation
import AppKit
import XCGLogger

class MenuDelegate: NSObject, NSMenuDelegate, NSSharingServiceDelegate {
    // MARK: Menu Outlets
    @IBOutlet weak var copyCommentMenuItem: NSMenuItem!
    @IBOutlet weak var openUrlMenuItem: NSMenuItem!
    @IBOutlet weak var tweetCommentMenuItem: NSMenuItem!
    @IBOutlet weak var addHandleNameMenuItem: NSMenuItem!
    @IBOutlet weak var removeHandleNameMenuItem: NSMenuItem!
    @IBOutlet weak var addToMuteUserMenuItem: NSMenuItem!
    @IBOutlet weak var reportAsNgUserMenuItem: NSMenuItem!
    @IBOutlet weak var openUserPageMenuItem: NSMenuItem!
    
    // MARK: General Properties
    let log = XCGLogger.defaultInstance()

    // MARK: Computed Properties
    var tableView: NSTableView {
        return MainViewController.sharedInstance.tableView
    }
    
    // MARK: - Object Lifecycle
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    // MARK: - NSMenu Overrides
    override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
        let clickedRow = self.tableView.clickedRow
        if clickedRow == -1 {
            return false
        }
        
        let message = MessageContainer.sharedContainer[clickedRow]
        if message.messageType != .Chat {
            return false
        }
        
        let chat = message.chat!
        
        switch menuItem {
        case self.copyCommentMenuItem, self.tweetCommentMenuItem:
            return true
        case self.openUrlMenuItem:
            return self.urlStringInComment(chat) != nil ? true : false
        case self.addHandleNameMenuItem:
            return (chat.isUserComment || chat.isBSPComment)
        case self.removeHandleNameMenuItem:
            let hasHandleName = (HandleNameManager.sharedManager.handleNameForChat(chat) != nil)
            return hasHandleName
        case self.addToMuteUserMenuItem, self.reportAsNgUserMenuItem:
            return (chat.isUserComment || chat.isBSPComment)
        case self.openUserPageMenuItem:
            return (chat.isRawUserId && (chat.isUserComment || chat.isBSPComment)) ? true : false
        default:
            break
        }
        
        return false
    }

    // MARK: - NSMenuDelegate Functions
    func menuWillOpen(menu: NSMenu) {
        self.resetMenu()
        
        let clickedRow = self.tableView.clickedRow
        if clickedRow == -1 {
            return
        }
        
        let message = MessageContainer.sharedContainer[clickedRow]
        
        if message.messageType != .Chat {
            return
        }
        
        self.configureMenu(message.chat!)
    }
    
    // MARK: Utility
    func resetMenu() {
    }
    
    func configureMenu(chat: Chat) {
    }

    // MARK: - Context Menu Handlers
    @IBAction func copyComment(sender: AnyObject) {
        let chat = MessageContainer.sharedContainer[self.tableView.clickedRow].chat!
        let toBeCopied = chat.comment!
        self.copyStringToPasteBoard(toBeCopied)
    }
    
    @IBAction func openUrl(sender: AnyObject) {
        let chat = MessageContainer.sharedContainer[self.tableView.clickedRow].chat!
        let urlString = self.urlStringInComment(chat)!
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: urlString)!)
    }
    
    @IBAction func tweetComment(sender: AnyObject) {
        let chat = MessageContainer.sharedContainer[self.tableView.clickedRow].chat!
        let live = NicoUtility.sharedInstance.live!
        
        let comment = chat.comment ?? ""
        let liveName = live.title ?? ""
        let communityName = live.community.title ?? ""
        let liveUrl = live.liveUrlString ?? ""
        let communityId = live.community.community ?? ""
        
        let status = "「\(comment)」/ \(liveName) (\(communityName)) \(liveUrl) #\(communityId)"
        
        let service = NSSharingService(named: NSSharingServiceNamePostOnTwitter)
        service?.delegate = self
        
        service?.performWithItems([status])
    }
    
    @IBAction func addHandleName(sender: AnyObject) {
        let chat = MessageContainer.sharedContainer[self.tableView.clickedRow].chat!
        MainViewController.sharedInstance.showHandleNameAddViewController(chat)
    }
    
    @IBAction func removeHandleName(sender: AnyObject) {
        let chat = MessageContainer.sharedContainer[self.tableView.clickedRow].chat!
        HandleNameManager.sharedManager.removeHandleNameWithChat(chat)
        MainViewController.sharedInstance.refreshHandleName()
    }
    
    @IBAction func addToMuteUser(sender: AnyObject) {
        let chat = MessageContainer.sharedContainer[self.tableView.clickedRow].chat!
        
        let defaults = NSUserDefaults.standardUserDefaults()
        var muteUserIds = defaults.objectForKey(Parameters.MuteUserIds) as [[String: String]]
        
        for muteUserId in muteUserIds {
            if chat.userId == muteUserId[MuteUserIdKey.UserId] {
                log.debug("mute userid [\(chat.userId)] already registered, so skip")
                return
            }
        }
        
        muteUserIds.append([MuteUserIdKey.UserId: chat.userId!])
        defaults.setObject(muteUserIds, forKey: Parameters.MuteUserIds)
        defaults.synchronize()
    }
    
    @IBAction func reportAsNgUser(sender: AnyObject) {
        let chat = MessageContainer.sharedContainer[self.tableView.clickedRow].chat!
        NicoUtility.sharedInstance.reportAsNgUser(chat) { (userId: String?) -> Void in
            if userId == nil {
                MainViewController.sharedInstance.logSystemMessageToTableView("Failed to report NG user.")
                return
            }
            
            MainViewController.sharedInstance.logSystemMessageToTableView("Completed to report NG user.")
        }
    }
    
    @IBAction func openUserPage(sender: AnyObject) {
        let chat = MessageContainer.sharedContainer[self.tableView.clickedRow].chat!
        let userPageUrlString = NicoUtility.sharedInstance.urlStringForUserId(chat.userId!)
        
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: userPageUrlString)!)
    }
    
    // MARK: - Internal Functions
    func urlStringInComment(chat: Chat) -> String? {
        if chat.comment == nil {
            return nil
        }
        
        return chat.comment!.extractRegexpPattern("(https?://[\\w/:%#\\$&\\?\\(\\)~\\.=\\+\\-]+)")
    }
    
    func copyStringToPasteBoard(string: String) -> Bool {
        let pasteBoard = NSPasteboard.generalPasteboard()
        pasteBoard.declareTypes([NSStringPboardType], owner: nil)
        let result = pasteBoard.setString(string, forType: NSStringPboardType)
        log.debug("copied \(string) w/ result \(result)")
        
        return result
    }
}