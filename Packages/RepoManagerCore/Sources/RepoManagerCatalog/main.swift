import Foundation
import RepoManagerCore

// Development-only documentation generator. This product is not linked into the app or Share extension.
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
let tools = ToolCatalog.all.sorted { ($0.group,$0.name) < ($1.group,$1.name) }
let rows:[JSON] = try tools.map { definition in
    var row = try JSON.parse(encoder.encode(definition)).object ?? [:]
    row["externalAgents"] = .bool(ExternalToolPolicy.permits(definition)); return .object(row)
}
FileHandle.standardOutput.write(try encoder.encode(rows))
