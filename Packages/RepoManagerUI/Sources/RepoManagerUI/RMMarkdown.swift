import SwiftUI

public struct RMMarkdown: View {
    public let text: String
    private struct Block: Identifiable { let id: Int; let content: String; let kind: Int }
    public init(_ text: String) { self.text = text }
    public var body: some View {
        VStack(alignment:.leading,spacing:RMLayout.rowGap) {
            ForEach(blocks) { block in
                if block.kind == 1 {
                    ScrollView(.horizontal) {
                        Text(block.content).font(.system(.footnote,design:.monospaced)).textSelection(.enabled).padding(RMLayout.rowGap)
                    }.background(RMPalette.input,in:RoundedRectangle(cornerRadius:RMLayout.rowCorner,style:.continuous))
                } else if block.kind == 2 {
                    ScrollView(.horizontal) {
                        Grid(alignment:.leading,horizontalSpacing:16,verticalSpacing:8) {
                            ForEach(Array(block.content.components(separatedBy:"\n").enumerated()),id:\.offset) { _, line in
                                GridRow {
                                    ForEach(Array(line.split(separator:"|").enumerated()),id:\.offset) { _, cell in
                                        Text(inline(String(cell))).font(RMType.meta).textSelection(.enabled)
                                    }
                                }
                            }
                        }.padding(RMLayout.rowGap)
                    }.background(RMPalette.input,in:RoundedRectangle(cornerRadius:RMLayout.rowCorner,style:.continuous))
                } else if block.kind == 3 {
                    Text(inline(block.content)).font(RMType.rowTitle).accessibilityAddTraits(.isHeader).frame(maxWidth:.infinity,alignment:.leading).padding(.top,RMLayout.unit)
                } else {
                    Text(inline(block.content)).font(RMType.body).lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                }
            }
        }
    }
    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown:string,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(string)
    }
    private var blocks: [Block] {
        var result: [Block] = []; var pending: [String] = []; var code = false; var table = false
        func flush(_ kind: Int) { if !pending.isEmpty { result.append(Block(id:result.count,content:pending.joined(separator:"\n"),kind:kind)); pending.removeAll() } }
        for line in text.components(separatedBy:"\n") {
            if line.hasPrefix("```") { flush(code ? 1 : table ? 2 : 0); code.toggle(); table = false; continue }
            if code { pending.append(line); continue }
            let trimmed = line.trimmingCharacters(in:.whitespaces)
            // ponytail: headings and bullets only; nested lists and block quotes stay as inline text.
            if let hashes = trimmed.firstIndex(where:{ $0 != "#" }), (1...6).contains(trimmed.distance(from:trimmed.startIndex,to:hashes)), trimmed[hashes] == " " {
                flush(table ? 2 : 0); table = false; pending = [String(trimmed[hashes...].dropFirst())]; flush(3); continue
            }
            let line = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ? "• "+trimmed.dropFirst(2) : line
            let isTable = trimmed.hasPrefix("|")
            if isTable != table { flush(table ? 2 : 0); table = isTable }
            if isTable && line.trimmingCharacters(in:CharacterSet(charactersIn:"|-: ")).isEmpty { continue }
            if trimmed.isEmpty && !table { flush(0); continue }
            pending.append(line)
        }
        flush(code ? 1 : table ? 2 : 0); return result
    }
}
