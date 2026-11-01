# How should a local Mac app send webhooks to an endpoint the person configures?

Researched 2026-11-01. This checks the review of [issue #36, "Webhook when a transcript is saved"](https://github.com/AlexDemzz/carbon/issues/36) against how mature webhook senders work. The question: Carbon is a menu-bar app with no server and no account. If it POSTs an event to a URL the person sets (their own agent, n8n, a home server), what should it do about delivery, retries, idempotency, payload, security, testing and wording? The sender here is a laptop that sleeps, goes offline and quits, which no hosted provider has to deal with.

Sources are the [Standard Webhooks spec](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md), the docs of Stripe, GitHub, Shopify, Svix and n8n, Apple's documentation, and source code pinned at a commit. Stripe's webhook page was served in French; quotes from it below are my translation. Anything I concluded myself is marked **(inference)**. Anything no primary source settles is marked **unverified**.

Pinned clones (shallow, read only):

- Standard Webhooks: [`standard-webhooks/standard-webhooks@ab68441`](https://github.com/standard-webhooks/standard-webhooks/tree/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554) (2026-10-30), spec version 1.0.0
- Home Assistant companion app (iOS, iPadOS and macOS): [`home-assistant/iOS@cb064d4`](https://github.com/home-assistant/iOS/tree/cb064d4eedc81eb399404b4f20e25344b348093b) (2026-10-29)

Line numbers below refer to these pins. Line numbers for Carbon refer to `main` at `082f3ac`.

## Short answer

| # | Review point | Verdict | Why, in one line |
|---|---|---|---|
| 1 | The webhook breaks README "Privacy". | **Confirmed** | README says "The only network traffic is Sparkle … and Apple's own speech model downloads". An opt-in webhook makes that false, and its payload carries titles and participant emails. |
| 2 | "Re-transcription" doesn't exist; say whether renames and Local Edits fire; none in v1. | **Amended** | Re-transcription does exist, but only for the live Meeting before its file is written, so it never rewrites a saved file. Hosted providers do send `*.updated` events, but they own the record. In Carbon the file is the person's, so "no update events in v1" holds. |
| 3 | In-memory 3 retries over about 6 minutes loses events; persist them. | **Confirmed, and the review undersells it** | Stripe retries for up to 3 days, Svix for about 27 hours, the Standard Webhooks example for about 75 hours, Shopify 8 times in 4 hours. A sleeping laptop burns 6 minutes of retries without a single real attempt. Persist an outbox and retry when the Mac wakes or the network returns. |
| 4 | Meeting `id` isn't enough; add a delivery id and a timestamp. | **Confirmed, with a correction** | Standard Webhooks' `webhook-id` is per *event*, the same on every retry. It is not a per-attempt id. Add `webhook-id`, `webhook-timestamp` and a body `timestamp`. The Meeting `id` stays as data. |
| 5 | Add `provider`, participants with email, settle absolute vs relative path, thin vs fat, versioning. | **Amended** | Add `provider`, but send participants as `{name, email}` objects, not the frontmatter's `Name <email>` string. Send both the relative and the absolute path. Keep it thin. Use a dot-delimited `type` whose schema never changes, rather than a separate version field. |
| 6 | "Settings", not "Preferences"; name events with GLOSSARY terms. | **Confirmed** | The code and README say Settings. `transcript.saved` names the Transcript, but the payload describes a Meeting. `meeting.transcribed` fits the GLOSSARY better **(inference)**. |
| 7 | Require HTTPS or warn on `http://`; HMAC vs static header; secret in Keychain. | **Amended** | App Transport Security already blocks `http://` to public hosts, since Carbon's Info.plist has no ATS exception. The real decisions are about the local network: `NSAllowsLocalNetworking` and the macOS 15 Local Network prompt. n8n's Webhook node checks a static header, not HMAC, so a static header (Keychain) is the right v1. Standard Webhooks HMAC can be added later without breaking anyone. |
| 8 | Drop "Include transcript" from v1. | **Confirmed, with a caveat** | Thin is right and keeps Transcript text on the Mac. But Stripe's thin events work because the consumer can call Stripe's API, and Carbon has none. A consumer that can't read `~/Carbon` (n8n cloud, say) gets nothing useful. The issue must say that the consumer is assumed to reach the file. |

Also covered below: the "Send test" button (§9), timeouts (§10), what counts as success and how to treat redirects (§10), concurrency and ordering (§11), and issues the review missed (§12).

**Recommended v1 shape** **(inference)**:

- One event type, sent once per Meeting, after `Library.create` writes the file. No update or delete events.
- A thin JSON body, `{type, timestamp, data}`, plus Standard Webhooks `webhook-id` and `webhook-timestamp` headers, plus an optional static auth header whose value lives in the Keychain.
- A persisted outbox in `~/Library/Application Support/Carbon`. It retries with backoff over about 3 days, sends again on wake and when the network comes back, and never blocks saving.
- "Send test" sends a separate test event, waits for the answer, and shows the status code inline.

## 1. Privacy: what the README promises today

README §Privacy, last bullet: "There's no account, no analytics and no server. The only network traffic is Sparkle checking for updates and Apple's own speech model downloads." ([README.md#L80](../../README.md)). Today the code bears that out: no Swift file in `App/` or `CarbonCore/` uses `URLSession` (`grep -rn URLSession`, 2026-11-01).

A webhook, even off by default, adds a third kind of traffic. Its body sends Meeting metadata off the Mac: the title, which comes from the calendar Event, and participant names and emails (§5). So the bullet has to change, and per CLAUDE.md in the same PR. Suggested wording **(inference)**: "…The only network traffic is Sparkle checking for updates, Apple's own speech model downloads and, if you set one, the webhook you choose, which receives each Meeting's title, date, participants and file path, never its Transcript."

The headline "No sign-in, no bot, no cloud" ([README.md#L5](../../README.md)) still holds: the endpoint is the person's own and opt-in **(inference)**.

## 2. Re-transcription, renames, Local Edits, and update events

### What the code does

- **Re-transcription exists, but only live.** "Re-transcribes the live Meeting from the start in `language`" (`App/Sources/AppModel+Languages.swift:64`). "Re-transcribes the Meeting in the language its identification confirmed" (`CarbonCore/Sources/CarbonCore/Recorder.swift:507`). Both happen while the Meeting is recorded. The file is written once, at the end, by `Library.create` with `.withoutOverwriting` (`CarbonCore/Sources/CarbonCore/Library.swift:71-103`). Its only caller is `Recorder.write` (`Recorder.swift:822-834`), which runs after diarization and voice recognition. So the issue's line "A rewritten file (re-transcription) sends the event again" describes something that cannot happen. The review is right to strike it, but wrong to say re-transcription doesn't exist.
- **Changes after the file exists:**
  - `rename(_:title:)` rewrites only the frontmatter `title` line, and the file name stays (`LibraryEdits.swift:30-33`).
  - `renameSpeaker` rewrites Speaker labels and can add a Participant with an email (`LibrarySpeakers.swift:11`).
  - `setColor` touches only `meetings.json` (`LibraryEdits.swift:35-38`).
  - `save(_:editedMarkdown:)` writes the person's Local Edit (`LibraryEdits.swift:42-55`).
  - `delete` moves the file to the Trash (`LibraryEdits.swift:64-78`).
  - `reconcile` follows files moved outside Carbon (`LibraryReconcile.swift:4-9`).
- **Launch recovery** finishes Meetings a crash interrupted (`RecorderRecovery.swift:17-20`). The review doesn't mention it. Such a Meeting's file appears at the next launch, possibly hours later, and should fire the event like any other. That works if the hook lives in `Library.create` or `Recorder.write` rather than in the UI **(inference)**.

### What mature providers do

- **Stripe** has update events. Its Event object carries `type` (e.g. `invoice.created`, `charge.refunded`) and a `data` object. `api_version` is "the Stripe API version used to render `data` when the event was created. The contents of `data` never change" ([Stripe, The Event object](https://docs.stripe.com/api/events/object)). Its newer "thin" events carry only a reference, and the handler fetches "the most recent version of the object" ([Stripe, Webhooks: thin event handler](https://docs.stripe.com/webhooks)).
- **Standard Webhooks** uses `user.created` and `contact.created` as examples, and recommends letting consumers "choose which event types they would like to receive" ([spec L240-L246](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L240-L246)).
- **Shopify** says it "doesn't guarantee ordering within a topic, or across different topics for the same resource". It tells apps to "use reconciliation jobs to periodically fetch data from Shopify", because "Webhook delivery isn't always guaranteed" ([Shopify, Best practices](https://shopify.dev/docs/apps/build/webhooks/best-practices)).

All three are the system of record, with an API behind the event. Carbon has no API: its "API" is the file, which the person may edit at any time.

**Verdict.** Send no update events in v1 **(inference)**:

- A title rename or Speaker rename would fire an event per keystroke-save unless debounced.
- A Local Edit is the person's text, and Carbon promises never to rewrite it ([README.md#L73](../../README.md)).
- A consumer that needs the latest state re-reads the file. That is what Stripe's thin events ask for anyway.

The issue should say this explicitly: "Renaming a Meeting or a Speaker, a Local Edit, a move and a Delete send nothing." Then it can list `meeting.updated` and `meeting.deleted` as possible later events, so the type naming leaves room for them (§6).

## 3. Offline, sleep, quit: retries and persistence

### What providers retry

| Sender | Schedule | Total span | Source |
|---|---|---|---|
| Stripe (live) | Exponential backoff | "up to three days" | [Stripe, Webhooks: Automatic retries](https://docs.stripe.com/webhooks) |
| Stripe (test) | 3 retries | "within a few hours" | same |
| Svix | Immediately, 5 s, 5 min, 30 min, 2 h, 5 h, 10 h, 10 h | about 27.6 h | [Svix, Retries](https://docs.svix.com/retries) |
| Standard Webhooks (example) | Immediately, 5 s, 5 min, 30 min, 2 h, 5 h, 10 h, 14 h, 20 h, 24 h | about 75.5 h | [spec L254-L271](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L254-L271) |
| Shopify | "up to eight times in a four-hour period", then the subscription may be removed | 4 h | [Shopify, Troubleshooting webhooks](https://shopify.dev/docs/apps/build/webhooks/troubleshooting-webhooks) |
| GitHub | None: "GitHub does not automatically redeliver failed deliveries." Manual redelivery for "the past 3 days". | 0 automatic | [GitHub, Handling failed deliveries](https://docs.github.com/en/webhooks/using-webhooks/handling-failed-webhook-deliveries), [Redelivering webhooks](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/redelivering-webhooks) |

The spec recommends "a retry schedule spanning multiple days, with an exponential backoff" and "some level of random jitter". It also says that after persistent failure, senders should "notify the consumers using other channels" and disable the endpoint ([spec L252-L256](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L252-L256)).

### Why a laptop needs more, not less

The issue's "10 s, 1 min, 5 min" spans about 6 minutes. Hosted senders retry because the *receiver* is down. Carbon also has to handle the *sender* being down: lid closed right after a Meeting, Wi-Fi off on a train, or the app quit. The most common case is a Meeting that ends, then the lid closes. All three retries then fall inside the sleep, or fail at once on wake before Wi-Fi rejoins. The event is lost **(inference)**.

"Mac offline: send once the network is back" is the right idea but needs a trigger:

- **Persist an outbox.** Write each pending delivery to a small JSON file in `~/Library/Application Support/Carbon`, next to `meetings.json` (ADR-0002), before the first attempt. Remove it on 2xx. This survives quit and crash. In-memory state cannot **(inference)**.
- **Count time on the wall clock, and attempt on events.** Store each delivery's `nextAttemptAt` as a date. Flush due deliveries at launch, on `NSWorkspace.didWakeNotification`, and when `NWPathMonitor` reports a satisfied path. This is better than a timer that sleeps through the night **(inference)**.
- **Don't count offline time as attempts.** Hold the attempt and retry when the path is back, rather than burning a retry on "not connected" **(inference)**.
- **Span about 3 days, like Stripe and the spec, then give up visibly** (§12). An agent may not want a week-old Meeting. The body `timestamp` (§4) lets it decide.

Apple's background `URLSession` looks like a fit but isn't:

- Its "transfers continue even when the app itself is suspended or terminated" guarantee is stated for iOS ([Apple, `background(withIdentifier:)`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))).
- Background tasks "automatically follow redirects" and the redirect delegate is "called only for tasks in default and ephemeral sessions" ([Apple, `urlSession(_:task:willPerformHTTPRedirection:…)`](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:))). That clashes with §10.
- Home Assistant, which does use a background session for its webhooks, has to write each body to a temporary file to upload it from there ([`WebhookManager.swift#L460-L470`](https://github.com/home-assistant/iOS/blob/cb064d4eedc81eb399404b4f20e25344b348093b/Sources/Shared/API/Webhook/Networking/WebhookManager.swift#L460-L470)).

A menu-bar app that runs whenever the person is logged in can use a default session plus its own outbox **(inference)**. For connectivity, `waitsForConnectivity` makes a default session wait "for connectivity to become available" instead of failing; it "is relevant only during the establishment of a connection". Background sessions ignore it and "always wait" ([Apple, `waitsForConnectivity`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity)). The resource timeout defaults to 7 days ([Apple, `timeoutIntervalForResource`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforresource)), so cap it.

## 4. Idempotency: Meeting id vs event id vs attempt

- **Standard Webhooks.** "The unique identifier is a unique identifier associated with a specific event triggered, and it remains the same no matter how many times a webhook that has failed is retried. The ID is often used as an idempotency key." The attempt timestamp is separate: "Every time an attempt is retried the timestamp of the attempt is updated, while the timestamp of the original event remains the same." ([spec L133-L137](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L133-L137)). The headers are `webhook-id`, `webhook-timestamp` ("integer unix timestamp") and `webhook-signature` ([L207-L224](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L207-L224)). The body carries its own `timestamp`, "when the event occurred (not necessarily the same of when it was delivered)" ([L56-L60](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L56-L60)).
- **Stripe.** "Webhook endpoints might occasionally receive the same event more than once", so log the event IDs you have processed. "In some cases, two separate Event objects are generated and sent": identify those by `data.object` id plus `event.type`. Don't use `created` to order events or detect duplicates ([Stripe, Webhooks: duplicate events, event ordering](https://docs.stripe.com/webhooks)).
- **GitHub.** `X-GitHub-Delivery` is "A globally unique identifier (GUID) to identify the event" ([GitHub, Webhook events and payloads](https://docs.github.com/en/webhooks/webhook-events-and-payloads)). Its best-practices page uses it to detect replays ([Best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks)).
- **Shopify** splits the two levels. Several subscriptions to one topic each get a different `X-Shopify-Webhook-Id` "but share the same `X-Shopify-Event-Id`". "Use `X-Shopify-Webhook-Id` to deduplicate individual deliveries" ([Shopify, Verify deliveries](https://shopify.dev/docs/apps/build/webhooks/verify-deliveries)).

**Verdict.** With one event type fired once per Meeting, the Meeting `id` would in practice be a working dedupe key. The review is still right to ask for a separate id, for three reasons:

1. "Send test" events (§9) must not collide with real ones.
2. Any later `meeting.updated` shares the Meeting id with the original event.
3. Consumers built on Standard Webhooks libraries look for `webhook-id`.

So: generate a UUID event id when the event is queued, persist it with the outbox entry, and send it unchanged on every retry as `webhook-id`. Send `webhook-timestamp` per attempt and `timestamp` in the body for when the file was written. Keep the Meeting `id` in `data` **(inference)**. A per-attempt id adds nothing a consumer can act on.

## 5. Payload: fields, paths, thin vs fat, versioning

### Thin vs fat

The spec describes "thin" payloads ("only include identifiers to the affected entities") and "full" ones, and says the choice isn't binary. It recommends staying "smaller than 20kb" ([spec L75-L121](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L75-L121)). Stripe's dashboard now offers thin events, labeled "recommended", next to snapshot events ([Stripe, Webhooks: create an event destination](https://docs.stripe.com/webhooks)). The issue's payload is a thin-plus-metadata event, which is the middle ground the spec describes. Keep it.

### Fields

- **`provider`: add it.** It is in the frontmatter ([README.md#L55](../../README.md)) and in the index (`Library.swift:87`). It is the one field a consumer is likely to route on, e.g. "only Zoom" **(inference)**.
- **Participants: structured, not the frontmatter string.**
  - The frontmatter writes `Dana Whitfield <dana@example.com>` ([README.md#L61-L63](../../README.md)). The issue sends `["Jane Doe"]`, which drops the email the agent most likely wants.
  - The review's "same format as frontmatter" would force every JSON consumer to parse `<…>` back out. At creation Carbon holds structured participants (`naming.participants`, `Recorder.swift:831`). Send `[{"name": "Dana Whitfield", "email": "dana@example.com"}]`, with `email` omitted or null when unknown **(inference)**.
  - These are the participants *when the file was written*. A later `renameSpeaker` can add one (`LibrarySpeakers.swift:11`), and the event won't reflect it (§2).
- **Path: send both.**
  - The relative path stays valid across a Library move. `meetings.json` paths are "relative to the Library folder, so they stay valid" (`LibraryMove.swift:10`).
  - The absolute path is what an agent over SSH can open with no extra knowledge. The Library is not always `~/Carbon`: it can be the legacy `~/Documents/Carbon` or wherever the person moved it (`Library.swift:54-67`).
  - Either can go stale if the person moves the file before delivery. Then `reconcile` finds it again by `id` (`LibraryReconcile.swift:6`). Document that the `id` in the frontmatter is the durable key **(inference)**.
  - The issue says the folder is `~/carbon`; the code creates `~/Carbon`.
- **`duration` as `"32:10"`** copies the frontmatter. That is consistent, but ambiguous for machines (mm:ss or h:mm?). Add `end` as an ISO 8601 timestamp, or `durationSeconds` **(inference)**.

### Versioning

The spec ties schema to type: "A payload associated with an event type should always have the same schema", like a REST path ([spec L242](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L242)). Stripe instead stamps `api_version` on each event, because it serves many API versions at once ([Stripe, The Event object](https://docs.stripe.com/api/events/object)). Carbon has one schema per release and no per-consumer version pinning. So follow the spec:

- a `type` field;
- additive changes only;
- a new type name for a breaking change.

A separate `version` field is optional, not needed **(inference)**.

Suggested body **(inference)**:

```json
{
  "type": "meeting.transcribed",
  "timestamp": "2026-01-15T15:02:41Z",
  "data": {
    "id": "6F1C2B8E-0A51-4C3A-9E0B-1F2D3C4B5A61",
    "provider": "Google Meet",
    "title": "Remote control kickoff",
    "start": "2026-01-15T14:30:00+01:00",
    "end": "2026-01-15T15:02:10+01:00",
    "language": "en-US",
    "participants": [{ "name": "Dana Whitfield", "email": "dana@example.com" }],
    "path": "2026/2026-01-15-remote-control-kickoff.md",
    "file": "/Users/jane/Carbon/2026/2026-01-15-remote-control-kickoff.md"
  }
}
```

## 6. Vocabulary

- **Settings, not Preferences.** The window is `SettingsView` with General, Languages, Ignored Apps, Permissions, Voice Prints and About tabs (`App/Sources/SettingsView.swift:4-27`). README says "Settings" throughout ([README.md#L22](../../README.md), [#L78-L79](../../README.md)). No Swift or Markdown file outside `docs/research` says "Preferences". Confirmed.
- **Event name.**
  - GLOSSARY defines **Transcript** as "the raw, machine-generated text of what was said in one Meeting" and **Meeting** as the call Carbon transcribed ([GLOSSARY.md](../../GLOSSARY.md)). The payload describes a Meeting: its id, title, Provider and Participants. The Transcript is exactly what it leaves out (§8).
  - The spec asks for "an hierarchical, and full-stop delimited" type, in `[a-zA-Z0-9_]` ([spec L244](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L244)).
  - So name the resource `meeting`. `meeting.created` reads like "the Meeting started", and **Detection** owns that idea. `meeting.transcribed` says the file now exists, and leaves room for `meeting.updated` and `meeting.deleted` **(inference)**.
  - "saved" is also loose: Carbon saves the file again on every rename and Local Edit (§2).
- **Participants, not attendees**, in the payload, per GLOSSARY. The issue already uses `participants`.

## 7. Security: transport, authentication, the secret

### HTTPS: ATS already decides most of it

- Carbon's `App/Info.plist` has no `NSAppTransportSecurity` key. ATS "requires that all HTTP connections made with the URL Loading System—typically using the `URLSession` class—use HTTPS" ([Apple, `NSAppTransportSecurity`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity)).
- So `http://n8n.example.com` would fail at the `URLSession` level unless Carbon adds `NSAllowsArbitraryLoads`. It should not **(inference)**. "Warn on http:// outside localhost" is therefore partly moot: Carbon cannot send it at all.
- The real decision is the local network. `NSAllowsLocalNetworking` covers "unqualified domains, `.local` domains, and IP addresses". From macOS 10.12 through 13, ATS allowed all three by default. "In iOS 17, iPadOS 17, and macOS 14, ATS no longer allows connections to IP addresses by default" ([Apple, `NSAllowsLocalNetworking`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)).
- So on current macOS, `http://192.168.1.10:5678/webhook` (a typical home n8n) and perhaps `http://127.0.0.1` likely fail without `NSAllowsLocalNetworking`. `http://localhost` and `http://homeserver.local` likely pass (**unverified**: test each form in a signed build).

Recommendation **(inference)**:

- Add `NSAllowsLocalNetworking`, and nothing broader. Then accept `https://` anywhere, and `http://` only for loopback, `.local`, unqualified hosts and private IPs, with a note that the payload travels unencrypted on the LAN.
- Say in Settings that `http://` to a public host is refused, instead of letting it fail at send time.
- No "ignore certificate errors" toggle. A home server with a self-signed certificate is a real case, but a Tailscale or Let's Encrypt name is the fix. GitHub, for one, recommends "that you leave SSL verification enabled" ([GitHub, Best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks)).

### Local Network privacy (macOS 15), missed by the review

- macOS 15 added Local Network privacy. "The first time a program accesses the local network, the system displays an alert asking the user to approve that access." "Making an outgoing TCP connection" to a local network address requires it, through any API, `URLSession` included ([Apple, TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)).
- Apps that do this "should include" `NSLocalNetworkUsageDescription` ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)). Carbon's Info.plist has none.
- TN3179 also warns that the system "may deny the operation immediately, before the user has responded to the alert", and advises `waitsForConnectivity` or retry logic.
- Consequences for Carbon:
  - Pointing the webhook at a LAN address triggers a system prompt.
  - "Send test" is the natural moment for it.
  - A denied prompt looks like a network failure, so Settings should mention it.
  - Loopback is not a "broadcast-capable network interface", so `localhost` should not prompt **(inference)**.
  - None of this appears in the README's Permissions story yet.

### Static header vs HMAC signature

- **Standard Webhooks** wants authenticity verified and signs `msg_id.timestamp.payload` with HMAC-SHA256. The secret is 24 to 64 random bytes, serialized as `whsec_…`. The signature is sent as `webhook-signature: v1,<base64>` ([spec L123-L224](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L123-L224)). Consumers should check the timestamp against "some allowable tolerance … to prevent replay attacks" ([L233](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L233)).
- **Stripe** signs a timestamp into `Stripe-Signature`, with a default 5-minute tolerance ([Stripe, Webhooks: replay attacks](https://docs.stripe.com/webhooks)).
- **GitHub** sends `X-Hub-Signature-256` when a secret is set ([GitHub, Webhook events and payloads](https://docs.github.com/en/webhooks/webhook-events-and-payloads)), and advises a secret instead of putting credentials in the URL ([Best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks)).
- **The consumers Carbon targets.** n8n's Webhook node lists Basic auth, Header auth, JWT auth and None ([n8n, Webhook node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)). HMAC checking would need a Code or Crypto node: it is not built in (**unverified** beyond that list).

**Verdict** **(inference)**:

- For v1, the issue's static header (name + value) is the right choice. It works with n8n's built-in Header auth, and over HTTPS to an endpoint the person owns it is adequate.
- HMAC buys replay protection and integrity, which matter most when the endpoint is public and the payload triggers actions.
- Standard Webhooks headers are additive ([spec L327-L333](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L327-L333)). Always send `webhook-id` and `webhook-timestamp` in v1. Add `webhook-signature` with a generated `whsec_` secret later, without breaking anyone.
- Never put the secret in the URL's query string: URLs end up in logs.

### Where the secret lives

- Not in `UserDefaults`: its plist in `~/Library/Preferences` is readable by any process running as the person **(inference)**. The Keychain is right.
- Apple says to use the SecItem API and to "default to targeting the data protection keychain" ([Apple, TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)). Its `kSecUseDataProtectionKeychain` page says it's "highly recommended that you set the value of this key to `true` for all keychain operations" ([Apple](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)).
- Carbon has no Keychain code today, and its entitlements hold only audio input and calendars (`App/Carbon.entitlements`).
- Whether the data protection keychain works in a Developer ID app without a keychain-access-groups entitlement and a provisioning profile is **unverified**. The file-based keychain needs none, but may prompt after the signing identity changes. Test both with a release-signed build before committing to one.

## 8. "Include transcript"

- The spec warns against big payloads: "you are imposing unnecessary load on the webhook consumer", and for large data, "consider uploading them somewhere and passing the link" ([spec L117-L121](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L117-L121)).
- An hour-long Transcript is tens of kilobytes. That is well past the 20 kB guideline, though under n8n's 16 MB cap ([n8n, Webhook node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)) **(inference)**.
- Sending it would also move the most sensitive data Carbon holds off the Mac, which §1 would then have to say.
- So dropping it from v1 is right.

The caveat: thin events assume the consumer can fetch the resource. Stripe's thin handler calls `fetchRelatedObject()` against Stripe's API ([Stripe, Webhooks](https://docs.stripe.com/webhooks)). Carbon's only "API" is the file. The issue's own consumer reads `~/Carbon` over SSH, so v1 works for it. A cloud n8n or Zapier flow cannot read the file, and gets only metadata. The issue should state this assumption, so "Include transcript" comes back as a deliberate later decision rather than a forgotten one **(inference)**.

## 9. "Send test"

- **GitHub**: when you create a webhook, it sends a distinct `ping` event, with `zen`, `hook_id` and `hook` fields ([GitHub, Webhook events and payloads: ping](https://docs.github.com/en/webhooks/webhook-events-and-payloads)).
- **Stripe** has no "send test" for a real event. You trigger real events in a test environment or with `stripe trigger payment_intent.succeeded` ([Stripe, Webhooks: Test your handler](https://docs.stripe.com/webhooks)), and every Event carries `livemode` ([The Event object](https://docs.stripe.com/api/events/object)).
- **Home Assistant**'s companion app has a dedicated `sendTest`. It posts a harmless request on the regular, non-background session with a 15 s timeout, and reports the result straight away ([`WebhookManager.swift#L526-L545`](https://github.com/home-assistant/iOS/blob/cb064d4eedc81eb399404b4f20e25344b348093b/Sources/Shared/API/Webhook/Networking/WebhookManager.swift#L526-L545)).
- **n8n**: a test webhook URL is registered only while the editor is "Listen for Test Event". The production URL is registered once the workflow is published ([n8n, Webhook node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)). People will paste one URL, test it, then need the other.

Recommendation **(inference)**:

- Use a distinct type, e.g. `webhook.test`, with the same `data` shape filled with sample values. Mark it with `"test": true`.
  - It must not be `meeting.transcribed`: an agent would otherwise go and process a file that doesn't exist.
  - The sample shape still lets an n8n user map fields.
- Send it immediately, outside the outbox, with no retries.
- Show the outcome inline in Settings: "Delivered (200)", "Failed: 401", "Timed out", "Local Network access denied".
- Save the URL and header first, so the test uses exactly what will be used.

## 10. Timeouts, success, redirects

- **Timeout.**
  - Standard Webhooks recommends 15 to 30 s ([spec L288-L290](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L288-L290)). Svix allows 30 s ([Svix, Retries](https://docs.svix.com/retries)). GitHub gives 10 s ([GitHub, Best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks)). Shopify gives 5 s ([Shopify, Troubleshooting](https://shopify.dev/docs/apps/build/webhooks/troubleshooting-webhooks)).
  - Carbon should use about 30 s. Its consumers are self-hosted, and n8n's "When Last Node Finishes" mode holds the response until the whole workflow ends ([n8n](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)). An agent that summarizes the Transcript before replying will time out, Carbon will retry, and the agent will run twice. The README should tell consumers to reply 2xx at once and work afterwards, as Stripe does: "return a successful status code (`2xx`) before any complex logic that could cause a timeout" ([Stripe, Webhooks](https://docs.stripe.com/webhooks)).
- **Success.** Only 2xx (200-299) counts as success. Any other status, and timeouts and connection resets, count as failure ([spec L273-L286](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L273-L286)). The spec adds:
  - `410 Gone`: disable the endpoint.
  - `429`, `502` and `504`: throttle.
  - Honor `retry-after`.
  - For Carbon: treat `410` as "stop and tell the person", and other 4xx and 5xx as retryable, since a misconfigured header (401) may be fixed **(inference)**.
- **Redirects: treat 3xx as failure.**
  - Standard Webhooks: "`3xx`: Failure. Following redirects causes unnecessary load". Svix: "Any other status code, including `3xx` redirects are treated as failures". Stripe treats redirect responses as failures and tells you to set the endpoint to the redirect target ([Stripe, Webhooks: fix HTTP status codes](https://docs.stripe.com/webhooks)).
  - `URLSession` follows redirects by default. Refuse them in `willPerformHTTPRedirection` by passing nil, which is possible only in a default or ephemeral session (§3).
  - Following a 301 or 302 may turn the POST into a GET without a body. The landing page's 200 would then count as success while nothing was delivered (**unverified** for current `URLSession`, **inference** as a risk). That makes refusing redirects a correctness issue, not just etiquette.
- Send a `User-Agent: Carbon/<version>` so the person can find Carbon's requests in their server logs. GitHub's always start with `GitHub-Hookshot/` ([GitHub](https://docs.github.com/en/webhooks/webhook-events-and-payloads)) **(inference)**.

## 11. Concurrency and ordering

- No provider promises order. Stripe "doesn't guarantee delivery of events in the order in which they're generated" ([Stripe, Webhooks: event ordering](https://docs.stripe.com/webhooks)). Shopify doesn't either ([Best practices](https://shopify.dev/docs/apps/build/webhooks/best-practices)). Carbon shouldn't promise it.
- In practice, deliver one at a time, oldest first, with a single URL **(inference)**:
  - Meetings end minutes apart at most, and one in-flight request is plenty.
  - Serial delivery keeps a home server from getting a burst after a night offline.
  - A delivery that keeps failing must not block later ones. Each entry has its own `nextAttemptAt`.
- Home Assistant goes further: it cancels a queued request when a newer one of the same kind replaces it ([`WebhookManager.swift#L569-L600`](https://github.com/home-assistant/iOS/blob/cb064d4eedc81eb399404b4f20e25344b348093b/Sources/Shared/API/Webhook/Networking/WebhookManager.swift#L569-L600)). Carbon fires one event per Meeting, so nothing replaces anything.

## 12. Issues the review missed

- **Local Network privacy prompt and ATS exceptions** (§7). The most likely v1 endpoint is a home n8n on a LAN IP over `http://`, and today it would fail on two counts. This needs `NSAllowsLocalNetworking`, `NSLocalNetworkUsageDescription`, a README line under Permissions, and testing.
- **Launch recovery fires events too** (§2). A crashed Meeting finished at the next launch should send its event then, with `timestamp` set to when its file was written.
- **Failure must be visible somewhere other than a log.**
  - The issue ends with "then log". Carbon's person never reads logs.
  - Standard Webhooks calls failure visibility and manual retry "immensely important" ([spec L319-L321](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L319-L321)) and advises telling the consumer "using other channels" ([L256](https://github.com/standard-webhooks/standard-webhooks/blob/ab6844147ce9cdb0d2dbf2e60d1ea85001fd2554/spec/standard-webhooks.md#L256)).
  - Minimum: Settings shows the last delivery's result. After the final failure, one notification. Optionally a "Send again" action on the Meeting **(inference)**.
- **What happens to pending deliveries when things change** **(inference)**:
  - **URL emptied:** drop the outbox.
  - **URL changed:** either re-target pending events or drop them. Pick one and write it in the issue.
  - **Meeting deleted before delivery:** drop its event, since the file is in the Trash.
- **No backfill.** Setting a URL does not send events for existing Meetings. Say so.
- **Duplicates are guaranteed, not hypothetical.** A timeout after the consumer received the body produces a retry. The README payload section must tell consumers to dedupe on `webhook-id` and reply 2xx before doing work (§10).
- **README placement.** The acceptance criterion "README documents the payload format" fits the CLAUDE.md rule, which says that what a person does goes in the README. But a full JSON schema may outgrow a user-facing README. A short README section linking to a `docs/webhook.md` reference is an option for the PR to decide **(inference)**.
- **Personal data on `http://` LAN.** Participant emails cross the LAN unencrypted if the person uses `http://`. Say so where the URL is entered (§7).

## Open questions and things I could not verify

- **ATS on macOS 26 for each local URL form.** Test `http://localhost`, `http://127.0.0.1`, `http://192.168.x.x`, `http://host.local` and `https://` with a self-signed certificate, in a Developer ID build with and without `NSAllowsLocalNetworking`. Apple's page says the macOS 14 change "no longer allows connections to IP addresses by default", but it doesn't spell out whether loopback IPs are covered.
- **Whether `localhost` triggers the Local Network prompt.** TN3179 scopes the prompt to broadcast-capable interfaces, which loopback is not, but I found no explicit statement.
- **`URLSession` redirect method rewriting** (POST to GET on 301/302) on current macOS.
- **Data protection keychain in a Developer ID app** without a provisioning profile.
- **Whether `Task.sleep` deadlines fire promptly after wake.** This only matters if the outbox uses timers rather than a stored `nextAttemptAt` checked on wake.
- **More desktop prior art.** I checked Home Assistant's companion app only. Its webhook design is close to what Carbon needs: a persisted queue, a separate test request and a 15 s timeout. I did not find first-party docs for outgoing webhooks with retries in Hazel, Raycast, Shortcuts or Obsidian plugins, and did not survey their source.
- **Svix's "send example" feature** in its App Portal: the docs page I fetched didn't describe it.
