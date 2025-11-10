//
//  PNGCompressor.swift
//  hummingbird
//
//  PNG Compressor - Color quantization compression using system built-in methods
//

import UIKit
import CoreImage
import ImageIO

class PNGCompressor {
    
    /// Compress PNG image
    /// - Parameters:
    ///   - image: Original image
    ///   - progressHandler: Progress callback (0.0 - 1.0)
    /// - Returns: Compressed PNG data
    static func compress(image: UIImage, progressHandler: ((Float) -> Void)? = nil) async -> Data? {
        progressHandler?(0.05)
        
        guard let cgImage = image.cgImage else {
            print("❌ [PNG Compression] Unable to get CGImage")
            return image.pngData()
        }
        
        progressHandler?(0.1)
        
        // Check if alpha channel exists
        let hasAlpha = cgImage.alphaInfo != .none &&
                       cgImage.alphaInfo != .noneSkipFirst &&
                       cgImage.alphaInfo != .noneSkipLast
        
        let originalSize = image.pngData()?.count ?? 0
        print("🔄 [PNG Compression] Starting compression - Size: \(cgImage.width)x\(cgImage.height), Alpha: \(hasAlpha), Original size: \(originalSize) bytes")
        
        progressHandler?(0.2)
        
        // Use CIImage for color quantization processing
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        
        progressHandler?(0.3)
        
        // Apply color quantization filter
        guard let quantizedImage = applyColorQuantization(ciImage: ciImage, hasAlpha: hasAlpha) else {
            print("⚠️ [PNG Compression] Color quantization failed, using original image")
            progressHandler?(1.0)
            return image.pngData()
        }
        
        progressHandler?(0.5)
        
        // Render to CGImage
        guard let outputCGImage = context.createCGImage(quantizedImage, from: quantizedImage.extent) else {
            print("⚠️ [PNG Compression] Rendering failed, using original image")
            progressHandler?(1.0)
            return image.pngData()
        }
        
        progressHandler?(0.7)
        
        // Use ImageIO for optimized PNG encoding
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            print("⚠️ [PNG Compression] Unable to create ImageDestination")
            progressHandler?(1.0)
            return image.pngData()
        }
        
        progressHandler?(0.8)
        
        // Set PNG compression options
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.8,  // Lossy compression quality
            kCGImagePropertyPNGCompressionFilter: 5  // PNG compression filter (5 = Paeth)
        ]
        
        CGImageDestinationAddImage(destination, outputCGImage, options as CFDictionary)
        
        progressHandler?(0.9)
        
        guard CGImageDestinationFinalize(destination) else {
            print("⚠️ [PNG Compression] Encoding failed")
            progressHandler?(1.0)
            return image.pngData()
        }
        
        let compressedData = mutableData as Data
        let compressionRatio = originalSize > 0 ? Double(compressedData.count) / Double(originalSize) : 1.0
        
        progressHandler?(1.0)
        
        print("✅ [PNG Compression] Compression complete - Compressed: \(compressedData.count) bytes, Ratio: \(String(format: "%.1f%%", compressionRatio * 100))")
        return compressedData
    }
    
    /// Apply color quantization
    private static func applyColorQuantization(ciImage: CIImage, hasAlpha: Bool) -> CIImage? {
        // Use CIColorPosterize filter for color quantization
        // This filter reduces the number of colors in the image, similar to pngquant
        guard let posterizeFilter = CIFilter(name: "CIColorPosterize") else {
            print("⚠️ [PNG Compression] Unable to create CIColorPosterize filter")
            return ciImage
        }
        
        posterizeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        // levels parameter controls the number of levels per color channel
        // Lower values mean fewer colors, higher compression, but lower quality
        // 8 is a good balance point, maintaining good visual quality while reducing file size
        posterizeFilter.setValue(8, forKey: "inputLevels")
        
        guard let outputImage = posterizeFilter.outputImage else {
            print("⚠️ [PNG Compression] Color quantization output failed")
            return ciImage
        }
        
        return outputImage
    }
}
