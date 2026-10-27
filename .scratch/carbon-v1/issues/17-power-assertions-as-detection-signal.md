# Power assertions as a Detection signal

Type: research
Status: open
Blocked by:

## Question

Should Detection use macOS power assertions (Zoom/Teams/Webex call assertions, Teams' "call in progress" only, browsers' "WebRTC has active PeerConnections") as a signal alongside mic-in-use and the calendar, as pasrom/meeting-transcriber ships (see "Prior art in Minute and meeting-transcriber")? Which signal starts a Meeting on its own, which only offers to, and does a browser WebRTC signal auto-start or ask, given "auto-transcribe by default" in "Carbon v1 product design"? Also fix the initial thresholds and ignored-process list from prior art (pasrom: ~6 s confirm, 15 s stop, 5 s back-to-back gap, 4 h cap; Minute: 120 s silence + 30 s countdown), since "Detection and auto-stop rules on real usage" is out of scope and tuning comes from dogfooding.
