// PROTOTYPE, throwaway. Foundation Models chunk-then-merge Summary over a test-set Meeting.
// Usage: summarize <meeting dir> <rolling|mapreduce> <out dir>
import Foundation
import FoundationModels

setvbuf(stdout, nil, _IONBF, 0)

@Generable
struct SummaryDelta {
    @Guide(description: "Net-new key points: decisions, conclusions, facts and topics that matter. One short sentence each.")
    var keyPoints: [String]
    @Guide(description: "Net-new next steps: concrete follow-up actions someone committed to or was asked to do, with the owner when known. Empty if none.")
    var nextSteps: [String]
}

@Generable
struct FinalSummary {
    @Guide(description: "The 3 to 8 most important key points of the whole meeting. One short sentence each.")
    var keyPoints: [String]
    @Guide(description: "The concrete next steps agreed in the meeting, with the owner when known. Empty if none.")
    var nextSteps: [String]
}

struct PassLog: Codable {
    var kind: String
    var inputTokens: Int
    var seconds: Double
    var error: String?
}

struct RunLog: Codable {
    var meeting: String
    var variant: String
    var language: String
    var contextSize: Int
    var transcriptTokens: Int
    var transcriptChars: Int
    var durationMinutes: Double
    var passes: [PassLog]
    var totalSeconds: Double
    var keyPoints: [String]
    var nextSteps: [String]
}

let args = CommandLine.arguments
let meetingDir = URL(fileURLWithPath: args[1])
let variant = args[2]
let outDir = URL(fileURLWithPath: args[3])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let meetingJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: meetingDir.appending(path: "meeting.json"))) as! [String: Any]
let meetingID = meetingJSON["id"] as! String
let language = meetingJSON["language"] as! String
let languageName = language == "fr" ? "French" : "English"
let durationMinutes = (meetingJSON["duration_s"] as! Double) / 60

// Transcript lines as Carbon would write them: "Me" or "Speaker A…", consecutive turns merged.
var labels: [String: String] = [:]
var lines: [String] = []
var lastLabel = ""
for row in try String(contentsOf: meetingDir.appending(path: "reference/segments.jsonl"), encoding: .utf8).split(separator: "\n") {
    let seg = try JSONSerialization.jsonObject(with: Data(row.utf8)) as! [String: Any]
    let text = (seg["text"] as! String).trimmingCharacters(in: .whitespaces)
    if text.isEmpty { continue }
    let speaker = seg["speaker"] as! String
    let label: String
    if seg["stream"] as! String == "me" {
        label = "Me"
    } else {
        if labels[speaker] == nil { labels[speaker] = "Speaker \(Character(UnicodeScalar(65 + labels.count)!))" }
        label = labels[speaker]!
    }
    if label == lastLabel { lines[lines.count - 1] += " " + text } else { lines.append("\(label): \(text)") }
    lastLabel = label
}

let model = SystemLanguageModel.default
let contextSize = model.contextSize
func tokens(_ s: String) async throws -> Int { try await model.tokenCount(for: s) }

let options = GenerationOptions(sampling: .greedy)
let outputReserve = 900
let promptOverhead = 450

let rollingInstructions = """
You summarize one part of a meeting transcript at a time for the person labelled "Me". \
You get the summary accepted so far and the next part of the transcript. \
Return only material that is new in this part and not already in the accepted summary. \
Write in \(languageName). No hallucinations: if nothing new fits a field, return an empty array. \
Do not invent tasks, owners or decisions to fill space.
"""

let mapInstructions = """
You take notes on one part of a meeting transcript for the person labelled "Me". \
Write in \(languageName). No hallucinations: if nothing fits a field, return an empty array. \
Do not invent tasks, owners or decisions to fill space.
"""

let reduceInstructions = """
You turn notes taken on consecutive parts of one meeting into the final summary for the person labelled "Me". \
Merge duplicates, keep what matters most, and keep only next steps that someone actually agreed to. \
Write in \(languageName). No hallucinations: do not add anything that is not in the notes.
"""

func chunk(_ lines: [String], budget: Int) async throws -> [String] {
    var chunks: [String] = []
    var current: [String] = []
    var currentTokens = 0
    for line in lines {
        let t = try await tokens(line) + 1
        if currentTokens + t > budget, !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
            current = []
            currentTokens = 0
        }
        current.append(line)
        currentTokens += t
    }
    if !current.isEmpty { chunks.append(current.joined(separator: "\n")) }
    return chunks
}

func normalized(_ s: String) -> String {
    s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
}

// Minute's merger: drop an item whose normalized text contains, or is contained by, an accepted one; keep the longer.
func merge(_ accepted: inout [String], _ new: [String]) {
    for item in new {
        let n = normalized(item)
        if n.isEmpty { continue }
        if let i = accepted.firstIndex(where: { let a = normalized($0); return a.contains(n) || n.contains(a) }) {
            if item.count > accepted[i].count { accepted[i] = item }
        } else {
            accepted.append(item)
        }
    }
}

func bullets(_ items: [String]) -> String { items.isEmpty ? "(none)" : items.map { "- \($0)" }.joined(separator: "\n") }

var passes: [PassLog] = []

@MainActor func run<T: Generable>(_ kind: String, _ instructions: String, _ prompt: String, _ type: T.Type) async -> T? {
    let session = LanguageModelSession(model: model, instructions: instructions)
    let started = Date()
    let inputTokens = (try? await tokens(instructions + prompt)) ?? -1
    do {
        let response = try await session.respond(to: prompt, generating: type, options: options)
        passes.append(PassLog(kind: kind, inputTokens: inputTokens, seconds: Date().timeIntervalSince(started)))
        print("  \(kind): \(inputTokens) tok, \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        return response.content
    } catch {
        passes.append(PassLog(kind: kind, inputTokens: inputTokens, seconds: Date().timeIntervalSince(started), error: "\(error)"))
        print("  \(kind): ERROR \(error)")
        return nil
    }
}

let transcript = lines.joined(separator: "\n")
let transcriptTokens = try await tokens(transcript)
print("\(meetingID) [\(variant)] context \(contextSize), transcript \(transcriptTokens) tok, \(lines.count) turns")
let started = Date()
var keyPoints: [String] = []
var nextSteps: [String] = []

switch variant {
case "rolling":
    // The accepted state grows, so chunk against the worst case: half the input budget kept for state.
    let budget = (contextSize - outputReserve - promptOverhead) * 2 / 3
    for (i, part) in try await chunk(lines, budget: budget).enumerated() {
        var prompt = "Accepted summary so far:\nKey points:\n\(bullets(keyPoints))\nNext steps:\n\(bullets(nextSteps))\n\nTranscript part \(i + 1):\n\(part)"
        // Trim the oldest accepted key points when the state would overflow the window.
        var kept = keyPoints
        while try await tokens(rollingInstructions + prompt) > contextSize - outputReserve, !kept.isEmpty {
            kept.removeFirst()
            prompt = "Accepted summary so far:\nKey points:\n\(bullets(kept))\nNext steps:\n\(bullets(nextSteps))\n\nTranscript part \(i + 1):\n\(part)"
        }
        if let delta = await run("chunk \(i + 1)", rollingInstructions, prompt, SummaryDelta.self) {
            merge(&keyPoints, delta.keyPoints)
            merge(&nextSteps, delta.nextSteps)
        }
    }
case "mapreduce":
    let budget = contextSize - outputReserve - promptOverhead
    var notes: [String] = []
    for (i, part) in try await chunk(lines, budget: budget).enumerated() {
        if let n = await run("map \(i + 1)", mapInstructions, "Transcript part \(i + 1):\n\(part)", SummaryDelta.self) {
            notes.append("Part \(i + 1)\nKey points:\n\(bullets(n.keyPoints))\nNext steps:\n\(bullets(n.nextSteps))")
        }
    }
    // Reduce in rounds until the notes fit one pass.
    var round = 1
    while true {
        let reduceBudget = contextSize - outputReserve - promptOverhead
        let groups = try await chunk(notes, budget: reduceBudget)
        var reduced: [FinalSummary] = []
        for (i, group) in groups.enumerated() {
            if let r = await run("reduce \(round).\(i + 1)", reduceInstructions, "Notes:\n\(group)", FinalSummary.self) { reduced.append(r) }
        }
        if groups.count <= 1 {
            keyPoints = reduced.first?.keyPoints ?? []
            nextSteps = reduced.first?.nextSteps ?? []
            break
        }
        notes = reduced.enumerated().map { "Section \($0.offset + 1)\nKey points:\n\(bullets($0.element.keyPoints))\nNext steps:\n\(bullets($0.element.nextSteps))" }
        round += 1
    }
default:
    fatalError("unknown variant \(variant)")
}

let total = Date().timeIntervalSince(started)
print("  total \(String(format: "%.1f", total)) s, \(keyPoints.count) key points, \(nextSteps.count) next steps")

let markdown = "## Key points\n\n\(bullets(keyPoints))\n\n## Next steps\n\n\(bullets(nextSteps))\n"
try markdown.write(to: outDir.appending(path: "\(meetingID).\(variant).md"), atomically: true, encoding: .utf8)
let log = RunLog(meeting: meetingID, variant: variant, language: language, contextSize: contextSize, transcriptTokens: transcriptTokens,
                 transcriptChars: transcript.count, durationMinutes: durationMinutes, passes: passes, totalSeconds: total,
                 keyPoints: keyPoints, nextSteps: nextSteps)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(log).write(to: outDir.appending(path: "\(meetingID).\(variant).json"))
