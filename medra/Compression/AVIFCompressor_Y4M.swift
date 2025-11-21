
import Foundation
import ffmpegkit
import UIKit

extension AVIFCompressor {
    
    /// Compress a Y4M file (YUV4MPEG2) to AVIF
    /// - Parameters:
    ///   - y4mURL: URL to the .y4m file
    ///   - quality: Quality value 0.1-1.0
    ///   - speedPreset: Encoding speed preset
    ///   - progressHandler: Optional progress callback
    /// - Returns: Compressed AVIF data or nil if failed
    static func compressFromY4M(
        y4mURL: URL,
        quality: Double = 0.85,
        speedPreset: AVIFSpeedPreset = .balanced,
        progressHandler: ((Float) -> Void)? = nil
    ) async -> AVIFCompressionResult? {
        print("🎬 [AVIF] Starting Y4M compression from \(y4mURL.path)")
        progressHandler?(0.05)
        
        guard let fileHandle = try? FileHandle(forReadingFrom: y4mURL) else {
            print("❌ [AVIF] Failed to open Y4M file")
            return nil
        }
        defer { try? fileHandle.close() }
        
        // Read Header
        // YUV4MPEG2 W... H... F... C...
        guard let headerData = readLine(from: fileHandle),
              let headerString = String(data: headerData, encoding: .ascii),
              headerString.hasPrefix("YUV4MPEG2 ") else {
            print("❌ [AVIF] Invalid Y4M header")
            return nil
        }
        
        var width: Int = 0
        var height: Int = 0
        var fps: Double = 30.0
        
        let components = headerString.split(separator: " ")
        for component in components {
            if component.hasPrefix("W") {
                width = Int(component.dropFirst()) ?? 0
            } else if component.hasPrefix("H") {
                height = Int(component.dropFirst()) ?? 0
            } else if component.hasPrefix("F") {
                let fpsString = component.dropFirst()
                let fpsParts = fpsString.split(separator: ":")
                if fpsParts.count == 2,
                   let num = Double(fpsParts[0]),
                   let den = Double(fpsParts[1]),
                   den > 0 {
                    fps = num / den
                }
            }
        }
        
        guard width > 0, height > 0 else {
            print("❌ [AVIF] Invalid Y4M dimensions: \(width)x\(height)")
            return nil
        }
        
        print("🎬 [AVIF] Y4M Header: \(width)x\(height) @ \(fps) fps")
        
        // Initialize Encoder
        guard let encoder = avifEncoderCreate() else {
            print("❌ [AVIF] Failed to create avifEncoder")
            return nil
        }
        defer { avifEncoderDestroy(encoder) }
        
        let quantizer = quantizerValue(for: quality)
        let quantizerValue = Int32(quantizer)
        encoder.pointee.minQuantizer = quantizerValue
        encoder.pointee.maxQuantizer = quantizerValue
        encoder.pointee.minQuantizerAlpha = quantizerValue
        encoder.pointee.maxQuantizerAlpha = quantizerValue
        encoder.pointee.speed = Int32(speedPreset.cpuUsedValue)
        encoder.pointee.maxThreads = Int32(max(1, ProcessInfo.processInfo.processorCount))
        encoder.pointee.autoTiling = AVIF_TRUE
        
        let timescale: UInt64 = 600
        encoder.pointee.timescale = timescale
        let durationInTimescales = UInt64(Double(timescale) / fps)
        
        // Frame Size for YUV420
        // Y: W * H
        // U: (W/2) * (H/2)
        // V: (W/2) * (H/2)
        let ySize = width * height
        let uvSize = (width / 2) * (height / 2)
        let frameSize = ySize + 2 * uvSize
        
        var frameIndex = 0
        
        while true {
            autoreleasepool {
                // Read FRAME header (usually "FRAME\n")
                guard let frameHeaderData = readLine(from: fileHandle),
                      let frameHeader = String(data: frameHeaderData, encoding: .ascii),
                      frameHeader.hasPrefix("FRAME") else {
                    return // End of file or invalid frame
                }
                
                // Read YUV data
                let yData = try? fileHandle.read(upToCount: ySize)
                let uData = try? fileHandle.read(upToCount: uvSize)
                let vData = try? fileHandle.read(upToCount: uvSize)
                
                guard let y = yData, let u = uData, let v = vData,
                      y.count == ySize, u.count == uvSize, v.count == uvSize else {
                    print("⚠️ [AVIF] Incomplete frame data at frame \(frameIndex)")
                    return
                }
                
                // Create avifImage for this frame
                guard let avifImage = avifImageCreate(UInt32(width), UInt32(height), 8, AVIF_PIXEL_FORMAT_YUV420) else {
                    print("❌ [AVIF] Failed to create avifImage")
                    return
                }
                defer { avifImageDestroy(avifImage) }
                
                // Allocate planes for YUV data
                avifImageAllocatePlanes(avifImage, avifPlanesFlags(AVIF_PLANES_YUV.rawValue))
                
                avifImage.pointee.colorPrimaries = avifColorPrimaries(UInt16(AVIF_COLOR_PRIMARIES_BT709))
                avifImage.pointee.transferCharacteristics = avifTransferCharacteristics(UInt16(AVIF_TRANSFER_CHARACTERISTICS_SRGB))
                avifImage.pointee.matrixCoefficients = avifMatrixCoefficients(UInt16(AVIF_MATRIX_COEFFICIENTS_BT709))
                avifImage.pointee.yuvRange = AVIF_RANGE_FULL
                
                // Copy data to avifImage planes
                // Y
                y.withUnsafeBytes { src in
                    for row in 0..<height {
                        let srcStart = row * width
                        let dstStart = Int(avifImage.pointee.yuvRowBytes.0) * row
                        if let srcBase = src.baseAddress, let dstBase = avifImage.pointee.yuvPlanes.0 {
                            memcpy(dstBase.advanced(by: dstStart), srcBase.advanced(by: srcStart), width)
                        }
                    }
                }
                
                // U
                let uvWidth = width / 2
                let uvHeight = height / 2
                u.withUnsafeBytes { src in
                    for row in 0..<uvHeight {
                        let srcStart = row * uvWidth
                        let dstStart = Int(avifImage.pointee.yuvRowBytes.1) * row
                        if let srcBase = src.baseAddress, let dstBase = avifImage.pointee.yuvPlanes.1 {
                            memcpy(dstBase.advanced(by: dstStart), srcBase.advanced(by: srcStart), uvWidth)
                        }
                    }
                }
                
                // V
                v.withUnsafeBytes { src in
                    for row in 0..<uvHeight {
                        let srcStart = row * uvWidth
                        let dstStart = Int(avifImage.pointee.yuvRowBytes.2) * row
                        if let srcBase = src.baseAddress, let dstBase = avifImage.pointee.yuvPlanes.2 {
                            memcpy(dstBase.advanced(by: dstStart), srcBase.advanced(by: srcStart), uvWidth)
                        }
                    }
                }
                
                let addResult = avifEncoderAddImage(encoder, avifImage, durationInTimescales, avifAddImageFlags(0))
                
                if addResult != AVIF_RESULT_OK {
                    let message = avifResultToString(addResult).flatMap { String(cString: $0) } ?? "unknown error"
                    print("❌ [AVIF] Failed to add frame \(frameIndex): \(message)")
                    return
                }
                
                frameIndex += 1
                if frameIndex % 10 == 0 {
                    DispatchQueue.main.async {
                        progressHandler?(0.1 + (Float(frameIndex) / 100.0) * 0.8)
                    }
                }
            }
        }
        
        var output = avifRWData(data: nil, size: 0)
        defer { avifRWDataFree(&output) }
        
        let finishResult = avifEncoderFinish(encoder, &output)
        guard finishResult == AVIF_RESULT_OK, let encodedPtr = output.data else {
            print("❌ [AVIF] avifEncoderFinish failed")
            return nil
        }
        
        let compressedData = Data(bytes: encodedPtr, count: output.size)
        print("✅ [AVIF] Y4M compression success - \(compressedData.count) bytes, \(frameIndex) frames")
        progressHandler?(1.0)
        
        // Estimate original size (raw YUV)
        let estimatedOriginalSize = frameIndex * frameSize
        
        return AVIFCompressionResult(
            data: compressedData,
            originalSize: estimatedOriginalSize,
            compressedSize: compressedData.count
        )
    }
    
    private static func readLine(from fileHandle: FileHandle) -> Data? {
        var lineData = Data()
        while true {
            guard let byteData = try? fileHandle.read(upToCount: 1), !byteData.isEmpty else {
                return lineData.isEmpty ? nil : lineData
            }
            let byte = byteData[0]
            if byte == 0x0A { // Newline
                return lineData
            }
            lineData.append(byte)
        }
    }
    
    // Helper to expose private quantizerValue if needed, or duplicate it here
    // Since we are in an extension, we can't access private static methods of the main struct easily if they are in another file
    // unless they are internal. Let's just duplicate it for safety or assume it's accessible if in same module (but it's private).
    // I'll duplicate it to be safe.
    private static func quantizerValue(for quality: Double) -> Int {
        let normalized = max(0.1, min(1.0, quality))
        let mapped = 10 + (1.0 - normalized) * 45.0
        return Int(mapped.rounded())
    }
}
