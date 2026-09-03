//
//  ReminderScheduler.swift
//  EusoTrip
//
//  The app's local reminder engine.
//
//  Before this existed there were four hand-rolled UNNotificationRequest sites
//  and no shared scheduling at all. Two of them were snoozes keyed on
//  `Int(Date().timeIntervalSince1970)` — a NEW identifier every time. That has
//  two consequences, both of which shipped:
//
//    · The request can never be named again, so it can never be cancelled.
//      A driver who snoozed a pre-trip nudge and then immediately started the
//      pre-trip still got "10-minute snooze is up. Ready to start your
//      pre-trip?" ten minutes later — a reminder firing for an event that had
//      already completed. `removePendingNotificationRequests` had zero call
//      sites anywhere in the app.
//    · Snoozing twice stacked two notifications instead of replacing one.
//
//  Every identifier here is DETERMINISTIC and derived from what the reminder is
//  about, so re-scheduling replaces, and completing the obligation cancels.
//
//  Honesty rule: a reminder restates a deadline the server has already proved.
//  It never invents one, and it is cancelled the moment the obligation is met
//  or disappears. A reminder about a thing that is no longer true is a lie with
//  a timer on it.
//

import Foundation
import UserNotifications

enum ReminderScheduler {

    // MARK: Identifiers

    /// Deterministic id for a reminder about a specific subject.
    /// `kind` is the reminder class ("prehaul", "pretrip", "appointment"),
    /// `subject` is what it is about (a load id, an appointment id).
    static func id(kind: String, subject: String) -> String {
        "euso.reminder.\(kind).\(subject)"
    }

    // MARK: Scheduling

    /// Schedule a reminder a fixed interval from now, replacing any existing
    /// reminder of the same kind for the same subject.
    static func schedule(
        kind: String,
        subject: String,
        title: String,
        body: String,
        after seconds: TimeInterval,
        category: String? = nil,
        userInfo: [String: Any] = [:]
    ) {
        guard seconds > 0 else { return }
        add(
            identifier: id(kind: kind, subject: subject),
            title: title, body: body, category: category, userInfo: userInfo,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
    }

    /// Schedule a reminder for a real calendar deadline — an appointment time,
    /// a credential expiry, a cutoff. Silently does nothing for a date already
    /// in the past rather than firing immediately, because a reminder about a
    /// deadline that has passed is not a reminder.
    static func schedule(
        kind: String,
        subject: String,
        title: String,
        body: String,
        at date: Date,
        category: String? = nil,
        userInfo: [String: Any] = [:]
    ) {
        guard date.timeIntervalSinceNow > 0 else { return }
        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        add(
            identifier: id(kind: kind, subject: subject),
            title: title, body: body, category: category, userInfo: userInfo,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
    }

    private static func add(
        identifier: String,
        title: String,
        body: String,
        category: String?,
        userInfo: [String: Any],
        trigger: UNNotificationTrigger
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            // Only schedule where the reminder can actually be seen. Provisional
            // delivers to Notification Center only — no lock screen, no banner,
            // no sound — so scheduling under it would create a reminder the
            // driver never receives while the app reports it as set.
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = userInfo
            if let category { content.categoryIdentifier = category }
            content.threadIdentifier = identifier

            // Same identifier replaces in place — UNUserNotificationCenter
            // semantics — so a second snooze never stacks a second banner.
            center.add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            ) { err in
                if let err {
                    print("[ReminderScheduler] schedule \(identifier) failed: \(err.localizedDescription)")
                }
            }
        }
    }

    // MARK: Cancellation

    /// Cancel one reminder. Call this the moment the obligation is met.
    static func cancel(kind: String, subject: String) {
        let ident = id(kind: kind, subject: subject)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ident])
        // Also pull it from the lock screen / Notification Center if it already
        // fired — a delivered reminder for a completed obligation is just as
        // wrong as a pending one.
        center.removeDeliveredNotifications(withIdentifiers: [ident])
        // The snooze copy PushService creates carries a derived identifier.
        center.removePendingNotificationRequests(withIdentifiers: ["snooze:\(ident)"])
        center.removeDeliveredNotifications(withIdentifiers: ["snooze:\(ident)"])
    }

    /// Cancel every reminder about one subject, whatever its kind — used when a
    /// load is delivered, cancelled, or reassigned away from this driver.
    static func cancelAll(subject: String) {
        let center = UNUserNotificationCenter.current()
        let suffix = ".\(subject)"
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter {
                ($0.hasPrefix("euso.reminder.") || $0.hasPrefix("snooze:euso.reminder."))
                    && $0.hasSuffix(suffix)
            }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}
