import Foundation
import Darwin

/// Opens the file once, rejects links/devices/FIFOs and checks that descriptor
/// before allocating a bounded read. No stat/open race or plaintext temp copy.
public enum BoundedFile {
    static func restrictPermissions(_ url:URL) throws {
        let descriptor = Darwin.open(url.path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw RMError.corruptRecord }; defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor,&metadata) == 0,metadata.st_mode & S_IFMT == S_IFREG,
              fchmod(descriptor,0o600) == 0 else { throw RMError.corruptRecord }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:url.path)
        #endif
    }
    public static func read(_ url:URL,limit:Int) throws -> Data {
        guard url.isFileURL,limit > 0,limit <= 90*1024*1024 else { throw RMError.invalidInput }
        let descriptor = Darwin.open(url.path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw RMError.corruptRecord }
        let file = FileHandle(fileDescriptor:descriptor,closeOnDealloc:true); defer { try? file.close() }
        var metadata = stat()
        guard fstat(descriptor,&metadata) == 0,metadata.st_mode & S_IFMT == S_IFREG else { throw RMError.corruptRecord }
        guard metadata.st_size >= 0,metadata.st_size <= limit else { throw RMError.tooLarge }
        let bytes = try file.read(upToCount:limit+1) ?? Data()
        guard bytes.count <= limit else { throw RMError.tooLarge }; return bytes
    }
}
