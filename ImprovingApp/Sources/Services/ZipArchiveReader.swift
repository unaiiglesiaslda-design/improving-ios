import Compression
import Foundation

/// Lightweight, zero-dependency ZIP archive reader built on Apple's `Compression` framework.
/// Supports Stored (method 0) and Deflate (method 8) entries by parsing the End of Central Directory
/// + Central Directory (reliable even when local file headers use bit-3 data descriptors, as macOS/iOS ZIPs do).
enum ZipArchiveReader {

    struct EntryInfo {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
    }

    enum ZipError: LocalizedError {
        case invalidArchive
        case unsupportedCompression(UInt16)
        case decompressionFailed
        case entryNotFound

        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "El archivo ZIP no tiene una estructura válida."
            case .unsupportedCompression(let m): return "Método de compresión ZIP no soportado (\(m))."
            case .decompressionFailed: return "No se pudo descomprimir el archivo dentro del ZIP."
            case .entryNotFound: return "No se encontró el archivo esperado dentro del ZIP."
            }
        }
    }

    static func listEntries(in fileURL: URL) throws -> [EntryInfo] {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw ZipError.invalidArchive }

        let searchLen = min(fileSize, 66_000)
        try handle.seek(toOffset: fileSize - searchLen)
        let tailData = handle.readData(ofLength: Int(searchLen))

        // Locate EOCD signature 0x06054b50 from the end
        let bytes = [UInt8](tailData)
        var eocdOffsetInTail: Int? = nil
        if bytes.count >= 22 {
            var i = bytes.count - 22
            while i >= 0 {
                if bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 {
                    eocdOffsetInTail = i
                    break
                }
                i -= 1
            }
        }
        guard let eocdIdx = eocdOffsetInTail else { throw ZipError.invalidArchive }

        let entryCount = Int(readUInt16LE(bytes, eocdIdx + 10))
        let cdSize = UInt64(readUInt32LE(bytes, eocdIdx + 12))
        let cdOffset = UInt64(readUInt32LE(bytes, eocdIdx + 16))
        guard cdOffset + cdSize <= fileSize else { throw ZipError.invalidArchive }

        try handle.seek(toOffset: cdOffset)
        let cdData = handle.readData(ofLength: Int(cdSize))
        let cdBytes = [UInt8](cdData)

        var cursor = 0
        var entries: [EntryInfo] = []
        entries.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            guard cursor + 46 <= cdBytes.count else { break }
            guard cdBytes[cursor] == 0x50,
                  cdBytes[cursor + 1] == 0x4B,
                  cdBytes[cursor + 2] == 0x01,
                  cdBytes[cursor + 3] == 0x02 else { break }

            let method = readUInt16LE(cdBytes, cursor + 10)
            var compSize = UInt64(readUInt32LE(cdBytes, cursor + 20))
            var uncompSize = UInt64(readUInt32LE(cdBytes, cursor + 24))
            let nameLen = Int(readUInt16LE(cdBytes, cursor + 28))
            let extraLen = Int(readUInt16LE(cdBytes, cursor + 30))
            let commentLen = Int(readUInt16LE(cdBytes, cursor + 32))
            var localOffset = UInt64(readUInt32LE(cdBytes, cursor + 42))

            let nameStart = cursor + 46
            let nameEnd = min(nameStart + nameLen, cdBytes.count)
            let name = String(bytes: cdBytes[nameStart..<nameEnd], encoding: .utf8) ?? ""

            // Parse ZIP64 extra field (0x0001) if sizes/offset are 0xFFFFFFFF
            let extraStart = nameEnd
            let extraEnd = min(extraStart + extraLen, cdBytes.count)
            if compSize == 0xFFFF_FFFF || uncompSize == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                var ePos = extraStart
                while ePos + 4 <= extraEnd {
                    let tag = readUInt16LE(cdBytes, ePos)
                    let blockLen = Int(readUInt16LE(cdBytes, ePos + 2))
                    if tag == 0x0001 {
                        var vPos = ePos + 4
                        if uncompSize == 0xFFFF_FFFF && vPos + 8 <= extraEnd {
                            uncompSize = readUInt64LE(cdBytes, vPos)
                            vPos += 8
                        }
                        if compSize == 0xFFFF_FFFF && vPos + 8 <= extraEnd {
                            compSize = readUInt64LE(cdBytes, vPos)
                            vPos += 8
                        }
                        if localOffset == 0xFFFF_FFFF && vPos + 8 <= extraEnd {
                            localOffset = readUInt64LE(cdBytes, vPos)
                        }
                        break
                    }
                    ePos += 4 + blockLen
                }
            }

            entries.append(
                EntryInfo(
                    name: name,
                    compressionMethod: method,
                    compressedSize: compSize,
                    uncompressedSize: uncompSize,
                    localHeaderOffset: localOffset
                )
            )
            cursor += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    static func extractEntryToTempFile(_ entry: EntryInfo, from zipURL: URL) throws -> URL {
        let handle = try FileHandle(forReadingFrom: zipURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: entry.localHeaderOffset)
        let localHdrData = handle.readData(ofLength: 30)
        let hdr = [UInt8](localHdrData)
        guard hdr.count == 30, hdr[0] == 0x50, hdr[1] == 0x4B, hdr[2] == 0x03, hdr[3] == 0x04 else {
            throw ZipError.invalidArchive
        }
        let fnameLen = Int(readUInt16LE(hdr, 26))
        let fextraLen = Int(readUInt16LE(hdr, 28))
        let payloadOffset = entry.localHeaderOffset + UInt64(30 + fnameLen + fextraLen)
        try handle.seek(toOffset: payloadOffset)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("improving_unzip_\(UUID().uuidString)_\((entry.name as NSString).lastPathComponent)")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: outURL)
        defer { try? outHandle.close() }

        if entry.compressionMethod == 0 {
            var remaining = entry.compressedSize
            let chunkCap = 128 * 1024
            while remaining > 0 {
                let toRead = Int(min(remaining, UInt64(chunkCap)))
                let chunk = handle.readData(ofLength: toRead)
                if chunk.isEmpty { break }
                outHandle.write(chunk)
                remaining -= UInt64(chunk.count)
            }
            return outURL
        }

        guard entry.compressionMethod == 8 else {
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }

        // Streaming raw Deflate decompression via Apple Compression framework
        var dummyStream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 1),
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        let dummyPtr = dummyStream.dst_ptr
        defer { dummyPtr.deallocate() }

        let initStatus = compression_stream_init(&dummyStream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus != COMPRESSION_STATUS_ERROR else {
            throw ZipError.decompressionFailed
        }
        defer { compression_stream_destroy(&dummyStream) }

        let inCap = 64 * 1024
        let outCap = 128 * 1024
        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: outCap)
        defer { outBuf.deallocate() }

        var remaining = entry.compressedSize
        var done = false

        while !done {
            let toRead = Int(min(remaining, UInt64(inCap)))
            let chunk = toRead > 0 ? handle.readData(ofLength: toRead) : Data()
            remaining -= UInt64(chunk.count)
            let isEOF = remaining == 0

            let stepResult = chunk.withUnsafeBytes { rawBuf -> compression_status in
                let srcBase = rawBuf.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer<UInt8>(bitPattern: 1)!
                dummyStream.src_ptr = srcBase
                dummyStream.src_size = chunk.count

                while true {
                    dummyStream.dst_ptr = outBuf
                    dummyStream.dst_size = outCap
                    let flags = isEOF ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                    let status = compression_stream_process(&dummyStream, flags)
                    let produced = outCap - dummyStream.dst_size
                    if produced > 0 {
                        outHandle.write(Data(bytes: outBuf, count: produced))
                    }
                    if status == COMPRESSION_STATUS_END {
                        done = true
                        return status
                    }
                    if status == COMPRESSION_STATUS_ERROR {
                        return status
                    }
                    if dummyStream.src_size == 0 && dummyStream.dst_size > 0 {
                        return status
                    }
                }
            }
            if stepResult == COMPRESSION_STATUS_ERROR {
                throw ZipError.decompressionFailed
            }
            if chunk.isEmpty && isEOF && !done {
                break
            }
        }
        return outURL
    }

    static func readEntryData(_ entry: EntryInfo, from zipURL: URL) throws -> Data {
        let tmp = try extractEntryToTempFile(entry, from: zipURL)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try Data(contentsOf: tmp)
    }

    private static func readUInt16LE(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    private static func readUInt32LE(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }

    private static func readUInt64LE(_ b: [UInt8], _ o: Int) -> UInt64 {
        var val: UInt64 = 0
        for shiftIdx in 0..<8 {
            val |= UInt64(b[o + shiftIdx]) << (UInt64(shiftIdx) * 8)
        }
        return val
    }
}
