//
//  AppDelegate.swift
//  Bookee
//
//  Handles Home Screen icon quick actions (long-press menu on the app icon).
//
//  iOS routes quick actions to UIWindowSceneDelegate.windowScene(_:performActionFor:) for
//  scene-based apps, not to the UIApplicationDelegate method. Cold launches are handled in
//  application(_:configurationForConnecting:options:) via options.shortcutItem, and warm
//  launches are handled in windowScene(_:performActionFor:completionHandler:). By conforming
//  to both protocols and registering self as the scene delegate via configurationForConnecting,
//  both are covered by one class.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate, UIWindowSceneDelegate {

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = Self.shortcutItems
        return true
    }

    /// Register AppDelegate as the UIWindowSceneDelegate so that
    /// windowScene(_:performActionFor:completionHandler:) receives warm-launch quick actions.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Handle quick action triggered at scene-connection time (cold launch via scene path)
        if let item = options.shortcutItem,
           let kind = AddSheetKind(rawValue: item.type) {
            NavigationStateManager.shared.pendingQuickActionKind = kind
        }
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = AppDelegate.self
        return config
    }

    // MARK: - UIWindowSceneDelegate

    /// Called for warm launches: app was backgrounded and user tapped a quick action.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if let kind = AddSheetKind(rawValue: shortcutItem.type) {
            NavigationStateManager.shared.pendingQuickActionKind = kind
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }

    // MARK: - Shortcut items

    // iOS shows at most 4 quick actions; order by most-likely-to-be-used.
    // Reallocate Funds is position 5 and will be hidden on devices that cap at 4.
    static let shortcutItems: [UIApplicationShortcutItem] = [
        UIApplicationShortcutItem(
            type: AddSheetKind.expense.rawValue,
            localizedTitle: "Add Expense",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "cart")
        ),
        UIApplicationShortcutItem(
            type: AddSheetKind.income.rawValue,
            localizedTitle: "Add Income",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "dollarsign.circle")
        ),
        UIApplicationShortcutItem(
            type: AddSheetKind.photo.rawValue,
            localizedTitle: "Add Photo",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "photo")
        ),
        UIApplicationShortcutItem(
            type: AddSheetKind.file.rawValue,
            localizedTitle: "Add File",
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "doc")
        ),

    ]
}
