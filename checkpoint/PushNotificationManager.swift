//
//  PushNotificationManager.swift
//  checkpoint
//
//  AppDelegate + FCM plumbing: requests notification permission on launch,
//  registers with APNs, and publishes the resulting FCM token so UserManager
//  can persist it on the user's Firestore doc. The Cloud Function that fans
//  out emergencies reads that token to push "[name] has triggered an emergency."
//

import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    static let fcmTokenDidChange = Notification.Name("PushNotificationManager.fcmTokenDidChange")

    /// Most recent FCM token, cached so UserManager can pick it up even if it
    /// starts listening after the delegate callback has already fired.
    private(set) static var currentToken: String?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Self.currentToken = fcmToken
        NotificationCenter.default.post(name: Self.fcmTokenDidChange, object: fcmToken)
    }

    // Show the banner even when the app is foregrounded so the friend still
    // gets a visible "[name] has triggered an emergency." alert.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
