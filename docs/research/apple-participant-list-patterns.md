# How Apple's apps show the people attached to an item

Researched 2026-10-30. Sources: the Human Interface Guidelines and API reference (read through the DocC JSON behind developer.apple.com), the Apple Support user guides for Calendar, Mail and Messages on Mac, and the macOS 26.4 SDK headers in Xcode 26.4. No user data was opened. The support site now defaults to the macOS 27 guides. Where a page has a Tahoe (26) version, I read that one. Anything a primary source does not establish is marked **unverified**. Conclusions I drew from a source, which the source does not state outright, are marked **(inference)**.

## Summary

| Question | Answer | Confidence |
|---|---|---|
| Calendar event Info: how are invitees shown? | A vertical list in its own grouped section, one name per row. A status symbol sits before each name. There is no avatar and no "Invitees:" label, and an "Add Invitees" row ends the list. | Support guide + its Tahoe screenshot |
| Calendar: does it show an organizer or an "N more" row? | Not described in any guide I found. | **unverified** |
| Mail message header: how are recipients shown? | As "Smart Addresses": the name alone. Hovering it shows an arrow, which opens a menu (see or copy the address, add to VIPs or to Contacts). | Support guide (pre-Tahoe version) |
| Mail: capsule tokens? | Tokens are documented for the **compose** address fields (`NSTokenField`), with a context menu on each token. | HIG |
| Mail: "and N more" truncation and the Details toggle in the header on macOS 26 | No primary source found. | **unverified** |
| Messages group details | A list of members by name, opened from the group icon. You remove a member by Control-clicking a name. | Support guide |
| Shared Notes, Freeform and Reminders | A system Collaboration button in the toolbar. Its popover lists collaborators, with Messages and FaceTime buttons. | HIG + `SWCollaborationView` docs |
| A public monogram or avatar view on macOS? | **No.** `CNAvatarView` is not in the public ContactsUI headers. The public API offers `CNContact.thumbnailImageData` and `CNContactViewController`. | SDK headers |
| A SwiftUI token field? | **No.** SwiftUI only has `searchable(text:tokens:)`. The editable token field is AppKit's `NSTokenField`. | SDK `.swiftinterface` |

## 1. Calendar: the event Info window

- On Tahoe, the guide says: "Double-click or force click the event, then click Add Invitees (or click next to the name of any existing invitees)." It also says "A symbol next to each invitee indicates the person's status—for example, available, busy, or replied yes, no, or maybe" ([Send and receive invitations, macOS 26](https://support.apple.com/guide/calendar/invite-people-to-events-icl1016/26.0/mac/26)).
- The guide's screenshot, *"Info window for an event, showing just invitees"* (`S0009_Invitees.png` on the same page), shows the layout. The window has stacked rounded sections: title and calendar, then date and alert, then **invitees**, then notes. In the invitees section, each row is a small outlined status glyph (here "?") and the name in body text. The last row is "⊕ Add Invitees" in placeholder grey. There is no heading or "Invitees:" label, no avatar and no email address.
- Calendar has seven invitee symbols. Four mean no response yet: available, busy, unknown availability, or not listed on the calendar server. Three mean a reply: accepted (a green ✓ in a circle), maybe, declined ([Symbols used in Calendar, macOS 26](https://support.apple.com/guide/calendar/symbols-used-in-calendar-symbls/26.0/mac/26)).
- Actions: "To remove an invitee, select the invitee, then press the Delete key." Control-clicking the **event** offers "Email All Participants or Message All Participants" ([same guide](https://support.apple.com/guide/calendar/invite-people-to-events-icl1016/26.0/mac/26)). The guide does not document the menu on an individual invitee. **(inference: Calendar treats an invitee row as a selectable item, not as a capsule.)**
- How the organizer appears, and whether a long list collapses to "N more", is **unverified**. The guides do not say.

## 2. Mail: the message header

- **Viewing a message.** "A Smart Address shows a recipient's name instead of their name and email address." To use one, "move the pointer over a person's name in an address field to show the Smart Address arrow. … Click the arrow to see or copy the person's email address or take another action, such as add the person to your VIPs or to Contacts" ([Use Smart Addresses, pre-Tahoe guide](https://support.apple.com/en-euro/guide/mail/mlhl0257dcd6/13.0/mac/10.15)). The setting still exists on Tahoe: "Use Smart Addresses: Show recipients' names but not their email addresses" ([Viewing settings](https://support.apple.com/guide/mail/change-viewing-settings-cpmlprefview/mac)). The macOS 26 and 27 Mail guides were restructured and no longer have the Smart Addresses page, so **the hover arrow on Tahoe is unverified**, though I expect it is unchanged **(inference)**.
- **Composing a message.** The HIG says: "Mail uses token fields for the address fields in the compose window", and "a recipient token in Mail includes a contextual menu with commands for editing the recipient name, marking the recipient as a VIP, and viewing the recipient's contact card" ([Token fields](https://developer.apple.com/design/human-interface-guidelines/token-fields)). The HIG lists token fields as macOS only.
- **Header fields** are the default set or a custom set, picked in Settings > Viewing > "Show message headers" ([Viewing settings](https://support.apple.com/guide/mail/change-viewing-settings-cpmlprefview/mac)). The `To:`/`Cc:` field labels, the sender's photo, the "and N more" truncation and the Details/Hide toggle all appear in current Mail, but I found **no primary source** describing them. They are **unverified**.
- **(inference)** So Mail draws a capsule **only where the list can be edited**. In the read-only header, a name is plain text that grows an affordance (the arrow) on hover.

## 3. Messages, FaceTime, shared documents, Contacts

- **Messages:** "Click the contact or group icon at the top, then click Add Member." The details view has "the list of members", then "Leave this Conversation" below it. To remove someone: "Control-click the name of the person you want to remove, then choose Remove From Group" ([Manage a group conversation](https://support.apple.com/guide/messages/manage-a-group-conversation-icht3268ad23/mac)). Whether each member row shows a photo is not stated, so it is **unverified**.
- **Shared Notes, Freeform and Reminders:** after sharing starts, apps show the system Collaboration button. "The system-provided Collaboration button reminds people that the content is shared and identifies who's sharing it." Its popover "lists collaborators and provides communication buttons that can open Messages or FaceTime". Below that come custom items and "Manage Shared File" ([Collaboration and sharing](https://developer.apple.com/design/human-interface-guidelines/collaboration-and-sharing)). The API is `SWCollaborationView`, available in macOS 13 and later, which "displays participants and sharing options" ([SWCollaborationView](https://developer.apple.com/documentation/sharedwithyou/swcollaborationview)). It needs a real CloudKit, iCloud Drive or custom collaboration, so it does not fit a list of meeting attendees **(inference)**.
- **FaceTime:** I found no primary source on how it lays out the participant list. **unverified**.
- **Contacts:** the public contact card on macOS is `CNContactViewController`, available in macOS 10.11 and later ([docs](https://developer.apple.com/documentation/contactsui/cncontactviewcontroller)). It can be shown in a popover. Photos come from `CNContact.thumbnailImageData` and `imageDataAvailable` (`Contacts.framework/Headers/CNContact.h`). The macOS SDK's ContactsUI headers are only `CNContactPicker`, `CNContactViewController` and the delegate. `CNAvatarView` exists only as a private symbol, so **a system monogram would need private API**, and Carbon's hand-drawn monogram is the only public option.

## 4. HIG guidance that applies

- **Labels and color:** "Use system-provided label colors to communicate relative importance". Secondary label is for "a subheading or supplemental text" ([Labels](https://developer.apple.com/design/human-interface-guidelines/labels)).
- **Typography:** the macOS text styles are Body 13/16, Callout 12/15, Subheadline 11/14, Headline 13/16 bold, and Title 3 15/20. The page adds that "macOS doesn't support Dynamic Type" ([Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
- **Layout:** "Group related items … use negative space, container shapes, or separator lines". "Use progressive disclosure … Use disclosure triangles, menus, or nested views to reduce how much content to initially display" ([Layout](https://developer.apple.com/design/human-interface-guidelines/layout)). A disclosure control should carry "a descriptive label" ([Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)).
- **Context menus:** "Support context menus consistently". "Always make context menu items available in the main interface, too". Keep submenus to one level, use no more than about three groups, "Hide unavailable menu items, don't dim them", and leave keyboard shortcuts out ([Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)).
- **Pop-up and pull-down buttons:** a pop-up button is for "mutually exclusive options". To "offer a list of actions" or "include a submenu", use a pull-down button ([Pop-up buttons](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons), [Pull-down buttons](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons)). A participant's actions menu is therefore a **pull-down**, which is what `Menu` gives Carbon today.
- **Inspectors:** "An inspector displays the details of the currently selected item, automatically updating its contents when the item changes", either in a panel or "a split view pane" ([Panels](https://developer.apple.com/design/human-interface-guidelines/panels)). SwiftUI's version is `.inspector(isPresented:content:)` in macOS 14 and later ([docs](https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:))).
- **APIs for a labelled block:** `LabeledContent`, in macOS 13 and later, gives "a layout that's consistent with other framework controls and automatically adapts to its container, like a form", and makes text values selectable "wherever possible" ([LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent)). `NSTokenField.TokenStyle` has the styles `default`, `none`, `plainSquared`, `rounded` and `squared` ([TokenStyle](https://developer.apple.com/documentation/appkit/nstokenfield/tokenstyle-swift.enum)). SwiftUI has no token field. The only token API is `searchable(text:tokens:…)` (SDK `SwiftUI.swiftinterface`).

## 5. Implications for Carbon's participant row

The Meeting pane is a read-only document view: participants are not typed into it. **(inference)** That makes Apple's precedent the *read* surfaces (the Mail header, the Calendar invitees section), not the compose token field. Carbon's current capsules with monograms look like the compose field.

### Option A: Mail-header line with Smart Addresses

Precedent: Mail's Smart Addresses (§2). One wrapping line under the title bar, read like a `To:` field.

```swift
HStack(alignment: .firstTextBaseline, spacing: 4) {
    Text("With").foregroundStyle(.secondary)              // field label, secondary color (Labels)
    FlowLayout(spacing: 0) {                               // names wrap; a comma is drawn inside each name
        ForEach(visible) { p in ParticipantName(p, isLast: …) }   // Menu label: name + hover chevron
        if hidden > 0 { Button("and \(hidden) more") { expanded = true }.buttonStyle(.link) }
    }
}
.font(.callout)                                            // 12 pt, below the 13 pt Body of the Transcript
```

- **Name:** plain `Text`, primary color. On hover a `chevron.down` appears (Mail's arrow). Clicking the name, the chevron, or Control-clicking opens the same pull-down: the email as a header row, Copy Email Address, New Email, a divider, Edit Participant…, Same Person As ▸. That is one submenu and about three groups, within the context-menu guidance.
- **Overflow:** show what fits in about two lines, then "and N more", which expands in place. This is progressive disclosure (§4); the Mail wording itself is **unverified**.
- **Avatars:** none. The Mail header precedent is name-only for recipients.
- **Pros:** densest; matches a reading pane; no custom capsule. **Cons:** each target is smaller than a capsule; the label word needs copy review.

### Option B: Calendar-style list section

Precedent: Calendar's Info window (§1). A grouped section with one row per person.

```swift
VStack(alignment: .leading, spacing: 0) {
    ForEach(visible) { p in
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle").foregroundStyle(.secondary)   // like the status-glyph slot
            Text(p.name)                                                         // body
            if let e = p.email, !p.isNamedByEmail { Text(e).foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(.vertical, 4).contentShape(.rect)
        .contextMenu { actions(p) }                         // like Messages' Control-click on a member
    }
    if hidden > 0 { DisclosureGroup("\(hidden) More Participants") { … } }
}
.padding(10).background(.quinary, in: .rect(cornerRadius: 10))   // the grouped container
```

- **Overflow:** about 5 rows, then a labelled disclosure.
- **Interaction:** Control-click opens the menu, and so does a hover chevron or an ellipsis button at the trailing edge, so the actions are also "in the main interface".
- **Pros:** scales to large meetings and leaves room for future status (joined, spoke, speaker label). **Cons:** pushes the Transcript down by a whole block; a Calendar-like card inside a document pane is heavier than Mail's single line.

### Option C: keep the tokens, aligned to the token-field precedent

Precedent: the HIG token field and its per-token context menu (§2, §4). Keep `FlowLayout` and capsules, but make them read like `NSTokenField` `.rounded` tokens:

- Drop the monogram, because Mail's tokens are text-only and no public system monogram exists (§3). Or keep it only once real `thumbnailImageData` exists.
- Text in `.callout` (12 pt). Keep the hover chevron, since an `NSTokenField` token also shows a menu affordance. Add a "+N" token that expands the list.
- **Pros:** the smallest change. **Cons:** a capsule in a read-only view borrows the *editable* control's look **(inference)**, so it still is not quite "100 % Apple".

### Recommendation

**Option A.** For a read-only list of people under a title, the closest first-party match is the Mail header with Smart Addresses: names in the primary color after a secondary-color field label, a hover arrow that opens a pull-down of address actions, and no avatars. Carbon's existing menu already matches the Smart Address menu (see/copy the address, act on the person), so only the label view changes, and the menu, popover and merge logic stay. Use `.callout` for the line so the Transcript header (Title 3) still leads, cap it at about two lines with an "and N more" link, and keep `.contextMenu` alongside the click menu for consistency. Move to Option B only if Carbon later shows per-participant status, where Calendar's glyph-plus-name rows are the precedent.
