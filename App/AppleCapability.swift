import Foundation

enum AppleCapability {
    private static let key = "com.apple.developer.private-cloud-compute"
    static var cloudKitProvisioned: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return (signatureEntitlements()?["com.apple.developer.icloud-container-identifiers"] as? [String])?.contains("iCloud.com.mesutcydev.repomanager") == true
        #endif
    }
    static var isProvisioned: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard signatureEntitlements()?[key] as? Bool == true else { return false }
        guard let url = Bundle.main.url(forResource:"embedded",withExtension:"mobileprovision") else { return true }
        guard let data = try? Data(contentsOf:url), data.count <= 16*1024*1024,
              let begin = data.range(of:Data("<?xml".utf8)),
              let end = data.range(of:Data("</plist>".utf8),in:begin.lowerBound..<data.endIndex),
              let profile = try? PropertyListSerialization.propertyList(from:data.subdata(in:begin.lowerBound..<end.upperBound),format:nil) as? [String:Any],
              let entitlements = profile["Entitlements"] as? [String:Any] else { return false }
        return entitlements[key] as? Bool == true
        #endif
    }
    /// Read only the actual Mach-O signature slot, never a string match in the binary.
    private static func signatureEntitlements() -> [String:Any]? {
        guard let url = Bundle.main.executableURL, let data = try? Data(contentsOf:url,options:.mappedIfSafe), data.count <= 256*1024*1024 else { return nil }
        func number(_ offset:Int,_ big:Bool = false) -> Int? {
            guard offset >= 0, offset+4 <= data.count else { return nil }
            let b = Array(data[offset..<offset+4]); return big ? Int(UInt32(b[0])<<24 | UInt32(b[1])<<16 | UInt32(b[2])<<8 | UInt32(b[3])) : Int(UInt32(b[3])<<24 | UInt32(b[2])<<16 | UInt32(b[1])<<8 | UInt32(b[0]))
        }
        guard number(0) == 0xfeedfacf, let count = number(16), count <= 10000 else { return nil }
        var offset = 32
        for _ in 0..<count {
            guard let command = number(offset), let length = number(offset+4), length >= 8, offset+length <= data.count else { return nil }
            if command == 0x1d {
                guard let start = number(offset+8), let size = number(offset+12), size >= 12, start+size <= data.count,
                      number(start,true) == 0xfade0cc0, let blobs = number(start+8,true), blobs <= 1000 else { return nil }
                for index in 0..<blobs {
                    let entry = start+12+index*8
                    guard entry+8 <= start+size, let slot = number(entry,true), let relative = number(entry+4,true) else { return nil }
                    if slot == 5 {
                        let begin = start+relative
                        guard begin >= start, begin+8 <= start+size, number(begin,true) == 0xfade7171,
                              let bytes = number(begin+4,true), bytes > 8, begin+bytes <= start+size else { return nil }
                        let entitlements = (try? PropertyListSerialization.propertyList(from:data.subdata(in:begin+8..<begin+bytes),format:nil)) as? [String:Any]
                        return entitlements
                    }
                }
                return nil
            }
            offset += length
        }
        return nil
    }
}
