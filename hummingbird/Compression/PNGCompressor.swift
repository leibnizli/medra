//
//  PNGCompressor.swift
//  hummingbird
//
//  PNG Compressor - Color quantization compression using system built-in methods
import UIKit
import Darwin

struct PNGCompressor { }

extension PNGCompressor {

    /// Compress a UIImage using the C API `CZopfliPNGOptimize`.
    /// Uses the in-memory C API instead of the C++ file-based API.
    static func compress(image: UIImage,
                         progressHandler: ((Float) -> Void)? = nil) async -> Data? {

        guard let pngData = image.pngData() else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {

                let result: Data? = pngData.withUnsafeBytes { (origBuf: UnsafeRawBufferPointer) in
                    guard let base = origBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
                    var options = CZopfliPNGOptions()
                    CZopfliPNGSetDefaults(&options)

                    var resultPtr: UnsafeMutablePointer<UInt8>? = nil
                    var resultSize: size_t = 0

                    let ret = CZopfliPNGOptimize(base,
                                                 size_t(origBuf.count),
                                                 &options,
                                                 0,
                                                 &resultPtr,
                                                 &resultSize)

                    guard ret == 0, let rptr = resultPtr, resultSize > 0 else {
                        return nil
                    }

                    let buffer = UnsafeBufferPointer(start: rptr, count: Int(resultSize))
                    let out = Data(buffer: buffer)

                    free(rptr)
                    return out
                }

                continuation.resume(returning: result)
            }
        }
    }
}
