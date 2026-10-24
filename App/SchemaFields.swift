import SwiftUI
import RepoManagerCore
import RepoManagerUI

/// Native editing for typed tool arguments. The JSON editor remains an explicit advanced option.
struct SchemaFields: View {
    let schema: JSON
    @Binding var value: JSON
    @Binding var invalidFields:Set<String>
    var depth = 0
    var path = ""
    private var required: Set<String> { Set(schema["required"].array?.compactMap(\.string) ?? []) }
    var body: some View {
        ForEach((schema["properties"].object ?? [:]).keys.sorted(),id:\.self) { key in
            let field = schema["properties"][key]
            VStack(alignment:.leading,spacing:RMLayout.elementGap) {
                if !required.contains(key) {
                    Toggle("Include \(label(key))",isOn:Binding(get:{ value[key] != .null },set:{ included in
                        set(included ? ToolFormView.sample(field) : .null,key:key)
                        if !included { let prefix = path+"/"+key; invalidFields = invalidFields.filter { $0 != prefix && !$0.hasPrefix(prefix+"/") } }
                    })).font(RMType.meta)
                }
                if required.contains(key) || value[key] != .null {
                    SchemaInput(title:label(key),fieldKey:key,schema:field,value:Binding(get:{ value[key] },set:{ set($0,key:key) }),invalidFields:$invalidFields,depth:depth,path:path+"/"+key)
                }
            }
        }
    }
    private func label(_ key:String) -> String { RMLocalization.fieldName(key) }
    private func set(_ field:JSON,key:String) { var object = value.object ?? [:]; if field == .null { object.removeValue(forKey:key) } else { object[key] = field }; value = .object(object) }
}
private struct SchemaInput: View {
    let title: String; let fieldKey: String; let schema: JSON
    @Environment(\.locale) private var locale
    @Binding var value: JSON
    @Binding var invalidFields:Set<String>
    var depth: Int
    let path:String
    @State private var jsonText = ""
    @State private var numberText = ""
    @ViewBuilder var body: some View {
        if let choices = schema["enum"].array?.compactMap(\.string), !choices.isEmpty {
            Picker(title,selection:Binding(get:{ value.string ?? choices[0] },set:{ value = .string($0) })) { ForEach(choices,id:\.self) { Text(RMLocalization.fieldName($0)).tag($0) } }
        } else if schema["type"].string == "boolean" {
            Toggle(title,isOn:Binding(get:{ value.bool ?? false },set:{ value = .bool($0) }))
        } else if schema["type"].string == "object" && depth < 4 && schema["properties"].object != nil {
            AnyView(DisclosureGroup(title) { SchemaFields(schema:schema,value:$value,invalidFields:$invalidFields,depth:depth+1,path:path) })
        } else if schema["type"].string == "array" && schema["items"]["type"].string == "string" {
            TextField("\(title) · comma separated",text:Binding(get:{ value.array?.compactMap(\.string).joined(separator:", ") ?? "" },set:{ value = .array($0.split(separator:",").map { .string($0.trimmingCharacters(in:.whitespacesAndNewlines)) }) })).autocorrectionDisabled()
        } else if ["object","array"].contains(schema["type"].string ?? "") {
            VStack(alignment:.leading,spacing:RMLayout.elementGap) {
                Text(title).font(RMType.detail.weight(.medium))
                TextEditor(text:$jsonText).font(.system(.footnote,design:.monospaced)).frame(minHeight:100).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onAppear { jsonText = value.pretty }
                    .onChange(of:jsonText) { _, s in
                        if let parsed = try? JSON.parse(Data(s.utf8)),(try? Schema.validate(parsed,against:schema)) != nil { value = parsed; invalidFields.remove(path) }
                        else { invalidFields.insert(path) }
                    }
                if invalidFields.contains(path) { Text("Enter valid JSON for this field before continuing.").font(RMType.meta).foregroundStyle(RMPalette.red) }
            }
        } else if ["integer","number"].contains(schema["type"].string ?? "") {
            VStack(alignment:.leading,spacing:RMLayout.unit) {
                TextField(title,text:$numberText).keyboardType(.numbersAndPunctuation)
                    .onAppear { if case .number(let number) = value { numberText = number.formatted(.number.grouping(.never).precision(.significantDigits(1...17)).locale(locale)) } }
                    .onChange(of:numberText) { _, text in
                        if let number = try? Double(text,format:.number.locale(locale),lenient:false),number.isFinite,(try? Schema.validate(.number(number),against:schema)) != nil {
                            value = .number(number); invalidFields.remove(path)
                        } else { invalidFields.insert(path) }
                    }
                if invalidFields.contains(path) { Text(schema["type"].string == "integer" ? String(localized:"Enter a valid whole number.") : String(localized:"Enter a valid number.")).font(RMType.meta).foregroundStyle(RMPalette.red) }
            }
        } else {
            TextField(title,text:Binding(get:{ value.string ?? "" },set:{ value = .string($0) }),axis:fieldKey.contains("body") || fieldKey.contains("content") ? .vertical : .horizontal)
                .lineLimit(1...8).autocorrectionDisabled().textInputAutocapitalization(.never)
        }
    }
}
