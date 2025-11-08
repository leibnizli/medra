import Foundation
import UIKit
import AVFoundation
import Combine

enum MediaCompressionError: Error {
    case imageDecodeFailed
    case videoExportFailed
    case exportCancelled
}

enum ImageFormat {
    case jpeg
    case heic
}

final class MediaCompressor {
    static func compressImage(_ data: Data, settings: CompressionSettings, preferredFormat: ImageFormat? = nil) throws -> Data {
        guard var image = UIImage(data: data) else { throw MediaCompressionError.imageDecodeFailed }
        
        // 修正图片方向，防止压缩后旋转
        image = image.fixOrientation()
        print("原始图片尺寸 - width:\(image.size.width), height:\(image.size.height)")

        // 检测原始图片格式，保持原有格式
        // 如果提供了 preferredFormat，优先使用它；否则从数据检测
        let format: ImageFormat
        if let preferredFormat = preferredFormat {
            format = preferredFormat
            print("📋 [格式检测] 使用预设格式: \(preferredFormat == .heic ? "HEIC" : "JPEG")")
        } else {
            format = detectImageFormat(data: data)
        }
        return encode(image: image, quality: CGFloat(settings.imageQuality), format: format)
    }
    
    private static func detectImageFormat(data: Data) -> ImageFormat {
        // 检查文件头来判断格式
        guard data.count > 12 else {
            print("📋 [格式检测] 数据太小，默认使用 JPEG")
            return .jpeg
        }
        
        let bytes = [UInt8](data.prefix(12))
        let hexString = bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("📋 [格式检测] 文件头 (前12字节): \(hexString)")
        
        // HEIC/HEIF 格式检测 (ftyp box)
        if bytes.count >= 12 {
            let ftypSignature = String(bytes: bytes[4..<8], encoding: .ascii)
            print("📋 [格式检测] ftyp 签名: \(ftypSignature ?? "nil")")
            if ftypSignature == "ftyp" {
                let brand = String(bytes: bytes[8..<12], encoding: .ascii)
                print("📋 [格式检测] brand: \(brand ?? "nil")")
                if brand?.hasPrefix("heic") == true || brand?.hasPrefix("heix") == true ||
                   brand?.hasPrefix("hevc") == true || brand?.hasPrefix("mif1") == true {
                    print("✅ [格式检测] 检测到 HEIC 格式")
                    return .heic
                }
            }
        }
        
        // JPEG 格式检测 (FF D8 FF)
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            print("✅ [格式检测] 检测到 JPEG 格式")
            return .jpeg
        }
        
        // 默认使用 JPEG
        print("⚠️ [格式检测] 未识别格式，默认使用 JPEG")
        return .jpeg
    }

    static func encode(image: UIImage, quality: CGFloat, format: ImageFormat) -> Data {
        switch format {
        case .jpeg:
            // 使用 MozJPEG 压缩
            let normalizedQuality = max(0.01, min(1.0, quality))
            if let mozjpegData = MozJPEGEncoder.encode(image, quality: normalizedQuality) {
                let originalSize = image.jpegData(compressionQuality: normalizedQuality)?.count ?? 0
                let compressedSize = mozjpegData.count
                let compressionRatio = originalSize > 0 ? Double(compressedSize) / Double(originalSize) : 0.0
                print("✅ [MozJPEG] 压缩成功 - 质量: \(normalizedQuality), 原始大小: \(originalSize) bytes, 压缩后: \(compressedSize) bytes, 压缩比: \(String(format: "%.2f%%", compressionRatio * 100))")
                return mozjpegData
            }
            // 如果 MozJPEG 失败，回退到系统默认
            print("⚠️ [MozJPEG] 压缩失败，回退到系统默认 JPEG 压缩 - 质量: \(normalizedQuality)")
            if let systemData = image.jpegData(compressionQuality: normalizedQuality) {
                print("✅ [系统默认] JPEG 压缩成功 - 大小: \(systemData.count) bytes")
                return systemData
            } else {
                print("❌ [系统默认] JPEG 压缩失败")
                return Data()
            }
        case .heic:
            if #available(iOS 11.0, *) {
                print("🔄 [HEIC] 开始 HEIC 压缩 - 质量: \(quality)")
                let mutableData = NSMutableData()
                
                guard let cgImage = image.cgImage else {
                    print("❌ [HEIC] 错误: cgImage 为 nil")
                    return Data()
                }
                
                guard let imageDestination = CGImageDestinationCreateWithData(mutableData, AVFileType.heic as CFString, 1, nil) else {
                    print("❌ [HEIC] 错误: 无法创建 CGImageDestination")
                    return Data()
                }
                
                let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
                CGImageDestinationAddImage(imageDestination, cgImage, options as CFDictionary)
                
                let success = CGImageDestinationFinalize(imageDestination)
                if success {
                    let heicData = mutableData as Data
                    print("✅ [HEIC] 压缩成功 - 大小: \(heicData.count) bytes")
                    return heicData
                } else {
                    print("❌ [HEIC] 错误: CGImageDestinationFinalize 失败")
                    return Data()
                }
            } else {
                print("⚠️ [HEIC] iOS 版本低于 11.0，不支持 HEIC")
                return Data()
            }
        }
    }

    static func compressVideo(
        at sourceURL: URL,
        settings: CompressionSettings,
        outputFileType: AVFileType = .mp4,
        progressHandler: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> AVAssetExportSession? {
        let asset = AVURLAsset(url: sourceURL)
        
        // 获取视频轨道信息
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(MediaCompressionError.videoExportFailed))
            return nil
        }
        
        let videoSize = videoTrack.naturalSize
        let bitrate = settings.calculateBitrate(for: videoSize)
        
        print("视频压缩 - 原始分辨率: \(videoSize), 目标比特率: \(bitrate) bps (\(Double(bitrate) / 1_000_000) Mbps)")
        
        // 创建输出 URL
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("compressed_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        
        // 删除已存在的文件
        try? FileManager.default.removeItem(at: outputURL)
        
        // 使用 Passthrough 预设，然后通过 VideoComposition 应用压缩设置
        // 注意：AVAssetExportSession 的预设选项有限，我们需要使用自定义的 videoComposition
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            // 如果 Passthrough 不可用，尝试使用 MediumQuality
            guard let fallbackSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetMediumQuality
            ) else {
                completion(.failure(MediaCompressionError.videoExportFailed))
                return nil
            }
            return configureExportSession(
                fallbackSession,
                asset: asset,
                videoTrack: videoTrack,
                videoSize: videoSize,
                bitrate: bitrate,
                outputURL: outputURL,
                outputFileType: outputFileType,
                progressHandler: progressHandler,
                completion: completion
            )
        }
        
        return configureExportSession(
            exportSession,
            asset: asset,
            videoTrack: videoTrack,
            videoSize: videoSize,
            bitrate: bitrate,
            outputURL: outputURL,
            outputFileType: outputFileType,
            progressHandler: progressHandler,
            completion: completion
        )
    }
    
    private static func configureExportSession(
        _ exportSession: AVAssetExportSession,
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        videoSize: CGSize,
        bitrate: Int,
        outputURL: URL,
        outputFileType: AVFileType,
        progressHandler: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> AVAssetExportSession {
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.shouldOptimizeForNetworkUse = true
        
        // 创建视频合成来保持原始分辨率和变换，并应用压缩设置
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        
        // 保持原始帧率
        let frameRate = videoTrack.nominalFrameRate
        if frameRate > 0 {
            videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        } else {
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        }
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(videoTrack.preferredTransform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        exportSession.videoComposition = videoComposition
        
        // 使用 AVAssetWriter 来精确控制比特率
        // 由于 AVAssetExportSession 无法直接设置比特率，我们需要使用 AVAssetWriter
        Task {
            do {
                let outputURL = try await compressVideoWithWriter(
                    asset: asset,
                    videoTrack: videoTrack,
                    videoSize: videoSize,
                    bitrate: bitrate,
                    outputURL: outputURL,
                    progressHandler: progressHandler
                )
                completion(.success(outputURL))
            } catch {
                // 如果 AVAssetWriter 失败，回退到使用 exportSession（虽然可能不会压缩）
                print("使用 AVAssetWriter 压缩失败，回退到 exportSession: \(error.localizedDescription)")
                
                // 设置进度监听
                let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    let progress = exportSession.progress
                    progressHandler(progress)
                    
                    if exportSession.status != .exporting {
                        timer.invalidate()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                
                // 开始导出
                exportSession.exportAsynchronously {
                    DispatchQueue.main.async {
                        timer.invalidate()
                        progressHandler(1.0)
                        
                        switch exportSession.status {
                        case .completed:
                            completion(.success(outputURL))
                        case .cancelled:
                            completion(.failure(MediaCompressionError.exportCancelled))
                        default:
                            let error = exportSession.error ?? MediaCompressionError.videoExportFailed
                            print("视频压缩失败: \(error.localizedDescription)")
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
        
        return exportSession
    }
    
    private static func compressVideoWithWriter(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        videoSize: CGSize,
        bitrate: Int,
        outputURL: URL,
        progressHandler: @escaping (Float) -> Void
    ) async throws -> URL {
        // 删除已存在的文件
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw MediaCompressionError.videoExportFailed
        }
        
        // 配置视频输出设置
        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSize.width,
            AVVideoHeightKey: videoSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
        videoInput.transform = videoTrack.preferredTransform
        videoInput.expectsMediaDataInRealTime = false
        
        guard assetWriter.canAdd(videoInput) else {
            throw MediaCompressionError.videoExportFailed
        }
        assetWriter.add(videoInput)
        
        // 处理音频轨道（如果有）
        var audioInput: AVAssetWriterInput?
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            let audioOutputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            
            let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
            audioWriterInput.expectsMediaDataInRealTime = false
            
            if assetWriter.canAdd(audioWriterInput) {
                assetWriter.add(audioWriterInput)
                audioInput = audioWriterInput
            }
        }
        
        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? MediaCompressionError.videoExportFailed
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        
        // 创建读取器
        guard let assetReader = try? AVAssetReader(asset: asset) else {
            throw MediaCompressionError.videoExportFailed
        }
        
        // 配置视频读取器
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        videoReaderOutput.alwaysCopiesSampleData = false
        
        if assetReader.canAdd(videoReaderOutput) {
            assetReader.add(videoReaderOutput)
        }
        
        // 配置音频读取器
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack = asset.tracks(withMediaType: .audio).first,
           let audioInput = audioInput {
            let audioOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM
                ]
            )
            audioOutput.alwaysCopiesSampleData = false
            
            if assetReader.canAdd(audioOutput) {
                assetReader.add(audioOutput)
                audioReaderOutput = audioOutput
            }
        }
        
        guard assetReader.startReading() else {
            throw assetReader.error ?? MediaCompressionError.videoExportFailed
        }
        
        let duration = asset.duration.seconds
        let videoQueue = DispatchQueue(label: "videoQueue")
        let audioQueue = DispatchQueue(label: "audioQueue")
        
        // 使用 DispatchGroup 来协调视频和音频的处理
        let group = DispatchGroup()
        
        // 处理视频
        group.enter()
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoInput.isReadyForMoreMediaData {
                guard let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() else {
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let progress = Float(presentationTime.seconds / duration)
                DispatchQueue.main.async {
                    progressHandler(min(progress, 0.95)) // 保留 5% 给音频和完成
                }
                
                if !videoInput.append(sampleBuffer) {
                    print("视频写入失败: \(assetWriter.error?.localizedDescription ?? "未知错误")")
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
        
        // 处理音频
        if let audioInput = audioInput, let audioReaderOutput = audioReaderOutput {
            group.enter()
            audioInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() else {
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                    
                    if !audioInput.append(sampleBuffer) {
                        print("音频写入失败: \(assetWriter.error?.localizedDescription ?? "未知错误")")
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }
        
        // 等待所有处理完成
        group.notify(queue: .main) {
            assetWriter.finishWriting {
                DispatchQueue.main.async {
                    progressHandler(1.0)
                }
            }
        }
        
        // 等待写入完成
        await withCheckedContinuation { continuation in
            // 使用定时器检查写入状态
            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                if assetWriter.status == .completed || assetWriter.status == .failed || assetWriter.status == .cancelled {
                    timer.invalidate()
                    continuation.resume()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        
        if assetWriter.status == .completed {
            return outputURL
        } else {
            throw assetWriter.error ?? MediaCompressionError.videoExportFailed
        }
    }
}

// MARK: - UIImage Extension for Orientation Fix
extension UIImage {
    func fixOrientation() -> UIImage {
        // 如果图片方向已经是正确的，直接返回
        if imageOrientation == .up {
            return self
        }
        
        guard let cgImage = cgImage else { return self }
        
        // 使用 UIGraphicsImageRenderer 重新绘制，自动处理方向
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // 使用 1.0 保持像素尺寸不变
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
