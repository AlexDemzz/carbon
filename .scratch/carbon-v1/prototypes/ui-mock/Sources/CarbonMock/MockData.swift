// PROTOTYPE, throwaway: fake Meetings.
import Foundation

enum MockData {
    static let dana = Attendee(name: "Dana Whitfield", email: "dana@northwind.io")
    static let marcus = Attendee(name: "Marcus Lee", email: "marcus@northwind.io")
    static let priya = Attendee(name: "Priya Raman", email: "priya@northwind.io")
    static let tom = Attendee(name: "Tom Becker", email: "tom@acme.com")
    static let claire = Attendee(name: "Claire Martin", email: "claire@studio-lumen.fr")
    static let sam = Attendee(name: "Sam Ortiz", email: "sam@acme.com")

    static func ago(days: Int, _ hour: Int, _ minute: Int) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    static func body(summary: String, lines: [(String, String, String)]) -> String {
        "## Summary\n\n\(summary)\n\n## Transcript\n\n" + lines.map { "**\($0.0)** [\($0.1)] \($0.2)" }.joined(separator: "\n")
    }

    static let meetings: [Meeting] = [
        Meeting(
            title: "Weekly design sync", date: ago(days: 0, 10, 0), duration: 42 * 60, provider: "Google Meet",
            attendees: [dana, marcus, priya], language: "English", color: .blue,
            body: body(summary: "- Onboarding stays out of v1; the menu bar icon is the only entry point.\n- The new empty state ships with the next build.\n\n**Next steps**\n- Priya: export the final icon from Icon Composer.\n- Marcus: draft the privacy page.", lines: [
                    ("Me", "00:00:04", "Okay, I think everyone's here. Let's start with the onboarding question."),
                    ("Dana Whitfield", "00:00:11", "I'd still argue for a single welcome screen, honestly."),
                    ("Speaker B", "00:00:19", "We tested that last quarter and nobody read it."),
                    ("Speaker C", "00:00:27", "The empty state can carry the explanation instead."),
                    ("Me", "00:00:35", "Agreed. No onboarding, the empty state explains what Carbon does."),
                    ("Speaker B", "00:01:02", "I'll draft the privacy page this week then."),
                    ("Speaker C", "00:01:15", "And I'll export the final icon from Icon Composer."),
                ])),
        Meeting(
            title: "1:1 Tom / Alex", date: ago(days: 1, 16, 30), duration: 28 * 60, provider: "Zoom",
            attendees: [tom], language: "English", color: nil,
            body: body(summary: "- Tom is moving to the platform team in November.\n- Hiring for his replacement starts next week.\n\n**Next steps**\n- Alex: write the job description.", lines: [
                    ("Tom Becker", "00:00:03", "So, I have some news. I'm moving to platform in November."),
                    ("Me", "00:00:09", "Congrats! That's what you wanted for a while."),
                    ("Tom Becker", "00:00:16", "Yeah. We should start hiring someone for the pricing work."),
                    ("Me", "00:00:24", "I'll write the job description by Friday."),
                ])),
        Meeting(
            title: "Point projet Lumen", date: ago(days: 2, 14, 2), duration: 55 * 60, provider: "Microsoft Teams",
            attendees: [claire], language: "French", color: .orange,
            body: body(summary: "- La maquette de la page d'accueil est validée.\n- Le lancement est décalé au 12 novembre.\n\n**Prochaines étapes**\n- Claire : envoyer les fichiers sources.", lines: [
                    ("Me", "00:00:02", "Bonjour Claire, on fait le point sur la page d'accueil ?"),
                    ("Them", "00:00:07", "Oui, j'ai intégré tes retours, la maquette est prête."),
                    ("Me", "00:00:15", "Parfait, on valide. Et pour la date de lancement ?"),
                    ("Them", "00:00:22", "Je propose le 12 novembre, ça laisse une semaine de tests."),
                ])),
        Meeting(
            title: "Meeting Oct 23, 9:15 AM", date: ago(days: 4, 9, 15), duration: 12 * 60, provider: "Slack",
            attendees: [], language: "English", color: nil,
            body: body(summary: "- Quick huddle about the staging outage; root cause was an expired certificate.", lines: [
                    ("Me", "00:00:01", "Is staging down for you too?"),
                    ("Speaker A", "00:00:05", "Yes, the certificate expired last night."),
                    ("Me", "00:00:11", "Okay, I'll renew it and add an alert."),
                ])),
        Meeting(
            title: "Acme pricing review", date: ago(days: 6, 11, 0), duration: 61 * 60, provider: "Google Meet",
            attendees: [tom, sam, dana], language: "English", color: .green,
            body: body(summary: "- Acme accepts the annual plan at the proposed price.\n- Legal review of the DPA is the only blocker.\n\n**Next steps**\n- Sam: send the DPA to legal.\n- Dana: prepare the order form.", lines: [
                    ("Sam Ortiz", "00:00:06", "We looked at the annual plan and the price works for us."),
                    ("Dana Whitfield", "00:00:14", "Great. Anything blocking on your side?"),
                    ("Sam Ortiz", "00:00:20", "Only legal, they need to read the DPA."),
                    ("Speaker C", "00:00:31", "I can send it today."),
                    ("Me", "00:00:40", "Then Dana prepares the order form in parallel."),
                ])),
        Meeting(
            title: "Interview: senior iOS engineer", date: ago(days: 9, 15, 0), duration: 47 * 60, provider: "Zoom",
            attendees: [marcus], language: "English", color: .purple,
            body: body(summary: "- Strong SwiftUI background, weaker on Core Audio.\n- Marcus recommends a second round.", lines: [
                    ("Marcus Lee", "00:00:02", "Thanks for joining. Can you walk us through your last project?"),
                    ("Speaker B", "00:00:09", "Sure, I built a SwiftUI journaling app with on-device search."),
                    ("Me", "00:00:30", "How did you handle audio recording?"),
                    ("Speaker B", "00:00:36", "Mostly AVAudioRecorder, I haven't gone deep into Core Audio."),
                ])),
    ]

    static var liveMeeting: Meeting {
        Meeting(
            title: "Weekly design sync", date: .now, duration: 0, provider: "Google Meet",
            attendees: [dana, marcus, priya], language: "English", color: nil,
            body: body(summary: "_Written when the Meeting ends._", lines: [
                ("Me", "00:00:02", "Can you all hear me?"),
                ("Them", "00:00:05", "Loud and clear."),
            ]),
            isLive: true)
    }
}
