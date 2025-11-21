//
//  GIFCompressor.swift
//  medra
//
//  Created by Agent on 2025/11/21.
//

import Foundation
import UIKit
import ffmpegkit

class GIFCompressor {
    
    static func compress(
        data: Data,
        settings: CompressionSettings,
        progressHandler: @escaping (Float) -> Void
    ) async -> Data? {
        // Create temp files
        let tempDir = FileManager.default.temporaryDirectory
        let inputID = UUID().uuidString
        let inputURL = tempDir.appendingPathComponent("input_\(inputID).gif")
        let outputURL = tempDir.appendingPathComponent("output_\(inputID).gif")
        
        do {
            try data.write(to: inputURL)
        } catch {
            print("❌ [GIF] Failed to write temp file: \(error)")
            return nil
        }
        
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // Construct FFmpeg command
        // fps filter
        let fps = settings.gifFrameRate
        
        // scale filter
        let scale = settings.gifScale
        let scaleString = String(format: "iw*%.2f", scale)
        
        // palette generation
        // Map quality (0.1-1.0) to max colors (16-256)
        let maxColors = max(16, min(256, Int(settings.gifQuality * 256)))
        
        // dithering
        let dither = settings.gifDithering ? "bayer:bayer_scale=5" : "none"
        
        // Filter complex
        // [0:v] fps=15,scale=iw*0.5:-1:flags=lanczos,split [a][b];[a] palettegen=max_colors=256 [p];[b][p] paletteuse=dither=bayer
        let filter = "fps=\(fps),scale=\(scaleString):-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=\(maxColors)[p];[s1][p]paletteuse=dither=\(dither)"
        
        let command = "-i \"\(inputURL.path)\" -vf \"\(filter)\" -y \"\(outputURL.path)\""
        
        print("🎬 [GIF] Command: ffmpeg \(command)")
        
        return await withCheckedContinuation { continuation in
            FFmpegKit.executeAsync(command) { session in
                guard let session = session else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let returnCode = session.getReturnCode()
                if ReturnCode.isSuccess(returnCode) {
                    print("✅ [GIF] Compression successful")
                    if let compressedData = try? Data(contentsOf: outputURL) {
                        continuation.resume(returning: compressedData)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    print("❌ [GIF] Compression failed")
                    print("Logs: \(session.getLogsAsString() ?? "")")
                    continuation.resume(returning: nil)
                }
            } withLogCallback: { log in
                // Optional: Parse logs for progress if needed
                // GIF encoding progress is hard to estimate accurately without total frames
            } withStatisticsCallback: { stats in
                // Optional: Update progress
            }
        }
    }
}
