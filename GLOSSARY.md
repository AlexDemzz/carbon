# Carbon

Carbon detects the meetings a person takes part in on their Mac and keeps a local, agent-readable Transcript of each.

## Language

**Meeting**:
A call the person took part in that Carbon transcribed.
_Avoid_: Call, conference, session, recording

**Provider**:
The meeting platform a Meeting was held on, such as Google Meet or Zoom.
_Avoid_: Source, integration, platform, service

**Meeting App**:
The app on the Mac the person joins a Meeting through, such as Chrome, Safari or the Zoom app. One Provider can be reached through several Meeting Apps, and one browser can host several Providers.
_Avoid_: Provider app, client, host app

**Detection**:
Carbon noticing that a Meeting is likely under way, which starts transcribing it or offers to.
_Avoid_: Trigger, auto-record

**Ignored App**:
An app whose use of the microphone never counts toward Detection, such as a dictation tool or a screen recorder.
_Avoid_: Blocklist, excluded app

**Transcript**:
The raw, machine-generated text of what was said in one Meeting, attributed to speakers.
_Avoid_: Notes, minutes, recording, summary

**Meeting Language**:
The spoken language a Meeting is transcribed in, chosen by the person rather than detected.
_Avoid_: Locale, transcription language

**Speaker**:
A distinct voice in a Transcript: the person themself ("Me") or another participant, unnamed ("Speaker A") until named.
_Avoid_: Participant, attendee, voice

**Participant**:
A person listed as taking part in a Meeting, in its frontmatter: the Event's attendees and anyone a Speaker was named after. Unlike a Speaker, a Participant may never have spoken.
_Avoid_: Attendee, member, guest

**Turn**:
One stretch of a Transcript attributed to a single Speaker, stamped with the time it starts.
_Avoid_: Segment, utterance, line

**Voice Print**:
The remembered signature of a named Speaker's voice, used to recognize them in later Meetings. The person's own Voice Print is learnt from the mic of Meetings held on headphones, where the mic hears only them, and recognizes them as `Me` when the mic is shared.
_Avoid_: Embedding, voice profile

**Summary**:
A short recap of a Meeting: key points and next steps. Not written in v1: "On-device summary quality" dropped it, so the Transcript is the whole product.
_Avoid_: Notes, minutes, recap

**Library**:
The set of Meetings, with their Transcripts and Summaries, stored on the person's Mac.
_Avoid_: Vault, archive, folder

**Local Edit**:
A change the person made to a Meeting in the Library.

**Deleted Meeting**:
A Meeting the person removed from the Library.
_Avoid_: Archived, trashed
