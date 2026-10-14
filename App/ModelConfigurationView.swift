import SwiftUI
import RepoManagerUI
import RepoManagerCore

struct ModelConfigurationView:View {
    @Binding var metadata:ModelMetadata
    let profile:ProviderProfile
    @State private var context = ""; @State private var output = ""; @State private var inputPrice = ""; @State private var outputPrice = ""
    @State private var customReasoning = false; @State private var capability = ReasoningCapabilities(kind:.providerDefault,levels:[],nativeAdaptive:true)
    @State private var protocolOverride:WireFormat?
    @State private var initialized = false; @State private var error:String?
    @State private var applied = false
    var body:some View {
        RMForm {
            Section("Model") { Text(metadata.id).textSelection(.enabled); Picker("Protocol",selection:$protocolOverride) {
                Text("Provider / catalog default").tag(WireFormat?.none)
                ForEach(WireFormat.allCases,id:\.self) { Text($0.rawValue).tag(Optional($0)) }
            } }
            Section("Explicit limits") {
                TextField("Context tokens (unknown if empty)",text:$context).keyboardType(.numberPad)
                TextField("Maximum output tokens",text:$output).keyboardType(.numberPad)
                Text("App budgets remain capped at 8,192 input and 4,096 output tokens; smaller model limits take priority.").font(RMType.meta)
            }
            Section("Pricing per million tokens") {
                TextField("Input price, USD",text:$inputPrice).keyboardType(.decimalPad)
                TextField("Output price, USD",text:$outputPrice).keyboardType(.decimalPad)
                Text("Empty prices remain unknown. Enter only verified prices for this exact model and destination.").font(RMType.meta)
            }
            Section("Reasoning contract") {
                Toggle("Configure explicit model capabilities",isOn:$customReasoning)
                if customReasoning {
                    Picker("Wire contract",selection:$capability.kind) { ForEach(ReasoningCapabilities.Kind.allCases.filter { $0 != .apple },id:\.self) { Text($0.rawValue).tag($0) } }
                    Toggle("Native adaptive reasoning",isOn:$capability.nativeAdaptive)
                    Toggle("Model allows reasoning to be disabled",isOn:$capability.canDisable)
                    ForEach(ReasoningPreference.allCases.filter { $0 != .automatic && $0 != .off },id:\.self) { level in
                        Toggle(level.title,isOn:Binding(get:{ capability.levels.contains(level) },set:{ selected in if selected { capability.levels.append(level) } else { capability.levels.removeAll { $0 == level } } }))
                    }
                    Text("Use the provider's documented capabilities. Unsupported effort levels or protocols can cause a request to fail. No retry or provider switch occurs.").font(RMType.meta)
                } else { Text("Reasoning adapts from catalog metadata and supported model families. Unrecognized models use answer-style guidance.").font(RMType.meta) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Apply model configuration") { apply() }.rmProminentButton()
            if applied { Label("Configuration applied. Save the provider to keep these settings.",systemImage:"checkmark.circle").font(RMType.meta).foregroundStyle(RMPalette.accentText) }
        }.navigationTitle("Model settings").onAppear {
            guard !initialized else { return }; initialized = true
            context = metadata.contextTokens.map(String.init) ?? ""; output = metadata.outputTokens.map(String.init) ?? ""
            inputPrice = metadata.inputCostPerMillion.map { String($0) } ?? ""; outputPrice = metadata.outputCostPerMillion.map { String($0) } ?? ""
            protocolOverride = metadata.format
            if let value = metadata.reasoning { customReasoning = true; capability = value }
            else { capability = ReasoningPolicy.capabilities(profile:profile,model:metadata.id) }
        }
    }
    private func apply() {
        do {
            func tokens(_ value:String) throws -> Int? { if value.isEmpty { return nil }; guard let n = Int(value),n > 0,n <= 2_000_000 else { throw RMError.invalidInput }; return n }
            func price(_ value:String) throws -> Double? { if value.isEmpty { return nil }; guard let n = Double(value),n.isFinite,n >= 0,n <= 10000 else { throw RMError.invalidInput }; return n }
            var copy = metadata; copy.contextTokens = try tokens(context); copy.outputTokens = try tokens(output)
            copy.inputCostPerMillion = try price(inputPrice); copy.outputCostPerMillion = try price(outputPrice)
            copy.format = protocolOverride; copy.reasoning = customReasoning ? capability : nil; metadata = copy; error = nil; applied = true
        } catch { applied = false; self.error = "Enter valid limits and prices. Values were not changed." }
    }
}
