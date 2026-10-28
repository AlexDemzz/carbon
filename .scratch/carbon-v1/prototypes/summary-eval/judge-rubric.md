# Judge rubric (PROTOTYPE)

For each Meeting you get the Transcript and, where the corpus has one, reference summaries written by humans. Summaries are labelled X and Y in random order; do not guess which system wrote which.

Score each Summary:

- **usefulness** 1–5: would the person labelled "Me" be happy to find this as the recap of the Meeting?
  5 = covers the main topics, decisions and follow-ups, nothing wrong; 4 = minor gaps; 3 = usable but misses something important or carries noise; 2 = misleading or mostly trivia; 1 = wrong or useless.
- **coverage**: of the reference's main points (or, without a reference, of the 5 most important things in the Transcript), how many does the Summary carry? Give "n / total".
- **wrong**: items that contradict the Transcript or are not supported by it (invented owners, decisions, numbers). List each.
- **next_steps**: 1–5, are the next steps real commitments from the Meeting, with the right owner, and nothing invented?
- **language**: is the Summary entirely in the Meeting's language (yes / no)?
- **noise**: trivia, duplicates or filler items (count).
