---
status: superseded by ADR-0003
---

# Read transcripts through a restricted Drive scope, launching unverified

Carbon reads Transcripts with `drive.meet.readonly` (fallback `drive.readonly`), both Google *restricted* scopes that require OAuth verification plus a yearly lab-run CASA assessment for a public app. We launch as an unverified "In production" External app (100-user cap, unverified-app warning) to measure demand before paying for verification.

## Considered Options

- **Meet REST API with `meetings.space.readonly`** (sensitive, no CASA): rejected because `conferenceRecords.list` only returns Meetings the person organized, and records expire after 30 days, so no history. A Calendar-driven workaround (meeting codes from Calendar events) is being prototyped; if it reaches Meetings organized by others, it supersedes this decision.
- **Verify and run CASA up front**: rejected until demand is proven; the assessment is lab-verified and repeats yearly.

## Consequences

- Workspace admins outside our org can block the unverified app for their users.
- The Google Cloud project is owned by the author's personal account, not an employer org.
