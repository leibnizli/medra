//
//  VideoFormatConversionView.swift
//  hummingbird
//
//  Video Format Conversion View
//

import SwiftUI
import PhotosUI
import AVFoundation
import ffmpegkit

struct VideoFormatConversionView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var mediaItems: [MediaItem] = []
    @State private var isConverting = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @StateObject private var settings = FormatSettings()
    
    private var hasLoadingItems: Bool {
        mediaItems.contains { $0.status == .loading }
    }
    
    private var isM4VSelected: Bool {
        settings.targetVideoFormat.lowercased() == "m4v"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部按钮
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Menu {
                        Button(action: { showingPhotoPicker = true }) {
                            Label("Select from Photos", systemImage: "photo.on.rectangle.angled")
                        }
                        
                        Button(action: { showingFilePicker = true }) {
                            Label("Select from Files", systemImage: "folder.fill")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Add Files")
                                .font(.system(size: 15, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isConverting || hasLoadingItems)
                    
                    Button(action: startConversion) {
                        HStack(spacing: 6) {
                            if isConverting || hasLoadingItems {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Text(isConverting ? "Processing" : hasLoadingItems ? "Loading" : "Start")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(mediaItems.isEmpty || isConverting || hasLoadingItems ? .gray : .green)
                    .disabled(mediaItems.isEmpty || isConverting || hasLoadingItems)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemGroupedBackground))
                
                Rectangle()
                    .fill(Color(uiColor: .separator).opacity(0.5))
                    .frame(height: 0.5)
            }
            
            // 设置区域
            VStack(spacing: 0) {
                HStack {
                    Text("Target Video Format")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Picker("", selection: $settings.targetVideoFormat) {
                        Text("MP4").tag("mp4")
                        Text("MOV").tag("mov")
                        Text("M4V").tag("m4v")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                    .padding(.leading, 16)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HEVC Encoding")
                            .font(.system(size: 15))
                            .foregroundStyle(isM4VSelected ? .secondary : .primary)
                        if isM4VSelected {
                            Text("M4V format only supports H.264")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $settings.useHEVC)
                        .labelsHidden()
                        .disabled(isM4VSelected)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .opacity(isM4VSelected ? 0.5 : (AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality) ? 1 : 0.5))
                .disabled(isM4VSelected || !AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality))
                
                Rectangle()
                    .fill(Color(uiColor: .separator).opacity(0.5))
                    .frame(height: 0.5)
            }
            .background(Color(uiColor: .systemBackground))
            
            // 文件列表
            if mediaItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "video.stack")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("Select videos to convert")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(mediaItems) { item in
                        FormatItemRow(item: item)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.visible)
                    }
                    .onDelete { indexSet in
                        guard !isConverting && !hasLoadingItems else { return }
                        withAnimation {
                            mediaItems.remove(atOffsets: indexSet)
                        }
                    }
                    .deleteDisabled(isConverting || hasLoadingItems)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Video Format")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItems, maxSelectionCount: 1, matching: .videos)
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.movie, .video], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                Task {
                    await loadFilesFromURLs(urls)
                }
            } catch {
                print("File selection failed: \(error.localizedDescription)")
            }
        }
        .onChange(of: settings.targetVideoFormat) { _, newFormat in
            if newFormat.lowercased() == "m4v" && settings.useHEVC {
                settings.useHEVC = false
            }
        }
    }
    
    private func startConversion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isConverting = true
        }
        
        Task {
            await MainActor.run {
                for item in mediaItems {
                    item.status = .pending
                    item.progress = 0
                    item.compressedVideoURL = nil
                    item.compressedSize = 0
                    item.errorMessage = nil
                }
            }
            
            for item in mediaItems {
                await convertItem(item)
            }
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isConverting = false
                }
            }
        }
    }
    
    private func convertItem(_ item: MediaItem) async {
        await MainActor.run {
            item.status = .processing
            item.progress = 0
        }
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        await convertVideo(item)
    }
    
    private func loadFilesFromURLs(_ urls: [URL]) async {
        await MainActor.run {
            mediaItems.removeAll()
        }
        
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let mediaItem = MediaItem(pickerItem: nil, isVideo: true)
            
            await MainActor.run {
                mediaItem.fileExtension = url.pathExtension.lowercased()
                mediaItems.append(mediaItem)
            }
            
            do {
                let data = try Data(contentsOf: url)
                
                await MainActor.run {
                    mediaItem.originalData = data
                    mediaItem.originalSize = data.count
                }
                
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("source_\(mediaItem.id.uuidString)")
                    .appendingPathExtension(url.pathExtension)
                try data.write(to: tempURL)
                
                await MainActor.run {
                    mediaItem.sourceVideoURL = tempURL
                    mediaItem.status = .pending
                }
                
                await loadAudioMetadata(for: mediaItem, url: tempURL)
            } catch {
                await MainActor.run {
                    mediaItem.status = .failed
                    mediaItem.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func convertVideo(_ item: MediaItem) async {
        print("[convertVideo] 开始视频转换")
        
        guard let sourceURL = item.sourceVideoURL else {
            print("❌ [convertVideo] 无法加载原始视频 URL")
            await MainActor.run {
                item.status = .failed
                item.errorMessage = "无法加载原始视频"
            }
            return
        }
        print("[convertVideo] 源视频 URL: \(sourceURL.path)")
        
        let asset = AVURLAsset(url: sourceURL)
        
        // 检测原始视频编码
        var originalCodec = item.videoCodec ?? "Unknown"
        let isOriginalHEVC = (originalCodec == "HEVC")
        var targetIsHEVC = settings.useHEVC
        
        let fileExtension = settings.targetVideoFormat
        
        // M4V 容器不支持 HEVC，强制使用 H.264
        if fileExtension.lowercased() == "m4v" && targetIsHEVC {
            targetIsHEVC = false
            print("⚠️ [convertVideo] M4V 容器不支持 HEVC，强制使用 H.264")
        }
        
        print("[convertVideo] 原始编码: \(originalCodec), 目标编码: \(targetIsHEVC ? "HEVC" : "H.264")")
        
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("converted_\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        
        print("[convertVideo] 目标格式: \(fileExtension)")
        print("[convertVideo] 输出 URL: \(outputURL.path)")
        
        // 判断是否只需要容器转换（不需要重新编码）
        // M4V 格式比较特殊，建议重新编码以确保兼容性
        let needsReencoding = (isOriginalHEVC != targetIsHEVC) || (fileExtension.lowercased() == "m4v")
        
        if !needsReencoding {
            // 只需要容器转换，使用 FFmpeg remux（无损、快速）
            print("🎬 [convertVideo] 只需容器转换，使用 FFmpeg remux")
            
            await withCheckedContinuation { continuation in
                FFmpegVideoCompressor.remux(inputURL: sourceURL, outputURL: outputURL) { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let url):
                            print("✅ [convertVideo] Remux 成功")
                            item.compressedVideoURL = url
                            if let data = try? Data(contentsOf: url) {
                                item.compressedSize = data.count
                                print("[convertVideo] 输出文件大小: \(data.count) bytes")
                            }
                            
                            let resultAsset = AVURLAsset(url: url)
                            if let videoTrack = resultAsset.tracks(withMediaType: .video).first {
                                let size = videoTrack.naturalSize
                                let transform = videoTrack.preferredTransform
                                let isPortrait = abs(transform.b) == 1.0 || abs(transform.c) == 1.0
                                item.compressedResolution = isPortrait ? CGSize(width: size.height, height: size.width) : size
                            }
                            
                            // 检测转换后的视频编码
                            if let codec = MediaItem.detectVideoCodec(from: url) {
                                item.compressedVideoCodec = codec
                            }
                            
                            item.outputVideoFormat = fileExtension
                            item.status = .completed
                            item.progress = 1.0
                            
                        case .failure(let error):
                            print("❌ [convertVideo] Remux 失败: \(error.localizedDescription)")
                            item.status = .failed
                            item.errorMessage = error.localizedDescription
                        }
                        continuation.resume()
                    }
                }
            }
        } else {
            // 需要重新编码，使用 FFmpeg 以保持原始比特率
            print("🎬 [convertVideo] 需要重新编码，使用 FFmpeg")
            
            // 获取原始视频的比特率
            var originalBitrate: Int = 0
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                let estimatedDataRate = try? await videoTrack.load(.estimatedDataRate)
                if let dataRate = estimatedDataRate, dataRate > 0 {
                    originalBitrate = Int(dataRate)
                    print("[convertVideo] 原始比特率: \(originalBitrate) bps (\(originalBitrate/1000) kbps)")
                }
            }
            
            // 如果无法获取比特率，使用默认值
            if originalBitrate == 0 {
                originalBitrate = 2_000_000 // 默认 2 Mbps
                print("[convertVideo] 使用默认比特率: \(originalBitrate) bps")
            }
            
            // 构建 FFmpeg 命令
            let codec = targetIsHEVC ? "hevc_videotoolbox" : "h264_videotoolbox"
            let bitrateKbps = originalBitrate / 1000
            
            var command = "-i \"\(sourceURL.path)\""
            command += " -c:v \(codec)"
            command += " -b:v \(bitrateKbps)k"  // 使用原始比特率
            command += " -c:a aac -b:a 128k"
            command += " -pix_fmt yuv420p"  // 确保像素格式兼容
            
            // 如果是 HEVC，添加兼容性标签
            if targetIsHEVC {
                command += " -tag:v hvc1"
            }
            
            command += " -movflags +faststart"
            command += " \"\(outputURL.path)\""
            
            print("[convertVideo] FFmpeg 命令: ffmpeg \(command)")
            
            await withCheckedContinuation { continuation in
                // 获取视频时长用于进度计算
                let duration = CMTimeGetSeconds(asset.duration)
                
                FFmpegKit.executeAsync(command, withCompleteCallback: { session in
                    guard let session = session else {
                        Task { @MainActor in
                            item.status = .failed
                            item.errorMessage = "FFmpeg session 创建失败"
                            continuation.resume()
                        }
                        return
                    }
                    
                    let returnCode = session.getReturnCode()
                    
                    Task { @MainActor in
                        if ReturnCode.isSuccess(returnCode) {
                            print("✅ [convertVideo] FFmpeg 转换成功")
                            item.compressedVideoURL = outputURL
                            if let data = try? Data(contentsOf: outputURL) {
                                item.compressedSize = data.count
                                print("[convertVideo] 输出文件大小: \(data.count) bytes")
                            }
                            
                            let resultAsset = AVURLAsset(url: outputURL)
                            if let videoTrack = resultAsset.tracks(withMediaType: .video).first {
                                let size = videoTrack.naturalSize
                                let transform = videoTrack.preferredTransform
                                let isPortrait = abs(transform.b) == 1.0 || abs(transform.c) == 1.0
                                item.compressedResolution = isPortrait ? CGSize(width: size.height, height: size.width) : size
                            }
                            
                            // 检测转换后的视频编码（使用异步版本）
                            Task {
                                if let codec = await MediaItem.detectVideoCodecAsync(from: outputURL) {
                                    await MainActor.run {
                                        item.compressedVideoCodec = codec
                                    }
                                }
                            }
                            
                            item.outputVideoFormat = fileExtension
                            item.status = .completed
                            item.progress = 1.0
                        } else {
                            print("❌ [convertVideo] FFmpeg 转换失败")
                            let errorMessage = session.getOutput() ?? "未知错误"
                            let lines = errorMessage.split(separator: "\n")
                            let errorLines = lines.suffix(5).joined(separator: "\n")
                            print("错误信息:\n\(errorLines)")
                            
                            item.status = .failed
                            item.errorMessage = "视频转换失败"
                        }
                        continuation.resume()
                    }
                }, withLogCallback: { log in
                    guard let log = log else { return }
                    let message = log.getMessage() ?? ""
                    
                    // 解析进度
                    if message.contains("time=") {
                        if let timeRange = message.range(of: "time=([0-9:.]+)", options: .regularExpression) {
                            let timeString = String(message[timeRange]).replacingOccurrences(of: "time=", with: "")
                            if let currentTime = self.parseTimeString(timeString), duration > 0 {
                                let progress = Float(currentTime / duration)
                                Task { @MainActor in
                                    item.progress = min(progress, 0.99)
                                }
                            }
                        }
                    }
                }, withStatisticsCallback: { statistics in
                    guard let statistics = statistics else { return }
                    let time = Double(statistics.getTime()) / 1000.0
                    if duration > 0 {
                        let progress = Float(time / duration)
                        Task { @MainActor in
                            item.progress = min(progress, 0.99)
                        }
                    }
                })
            }
        }
        print("[convertVideo] 视频转换流程结束")
    }
    
    // 解析时间字符串 (HH:MM:SS.ms)
    private func parseTimeString(_ timeString: String) -> Double? {
        let components = timeString.split(separator: ":")
        guard components.count == 3 else { return nil }
        
        guard let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else {
            return nil
        }
        
        return hours * 3600 + minutes * 60 + seconds
    }
    
    // 加载音频项（优化版本）
    private func loadAudioItemOptimized(_ item: PhotosPickerItem, _ mediaItem: MediaItem) async {
        // 检测音频格式
        await MainActor.run {
            if let ext = item.supportedContentTypes.first?.preferredFilenameExtension?.lowercased() {
                mediaItem.fileExtension = ext
            } else {
                mediaItem.fileExtension = "audio"
            }
        }
        
        // 尝试使用 URL 方式加载
        if let url = try? await item.loadTransferable(type: URL.self) {
            await MainActor.run {
                mediaItem.sourceVideoURL = url  // 复用这个字段
                
                // 快速获取文件大小
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                    mediaItem.originalSize = fileSize
                }
                
                mediaItem.status = .pending
                
                // 在后台异步获取音频信息
                Task {
                    await loadAudioMetadata(for: mediaItem, url: url)
                }
            }
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            await MainActor.run {
                mediaItem.originalData = data
                mediaItem.originalSize = data.count
                
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("source_\(mediaItem.id.uuidString)")
                    .appendingPathExtension(mediaItem.fileExtension)
                try? data.write(to: tempURL)
                mediaItem.sourceVideoURL = tempURL
                
                mediaItem.status = .pending
                
                Task {
                    await loadAudioMetadata(for: mediaItem, url: tempURL)
                }
            }
        }
    }
    
    // 加载音频元数据
    private func loadAudioMetadata(for mediaItem: MediaItem, url: URL) async {
        let asset = AVURLAsset(url: url)
        
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            await MainActor.run {
                mediaItem.duration = durationSeconds
            }
            
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = tracks.first {
                let formatDescriptions = audioTrack.formatDescriptions as! [CMFormatDescription]
                if let formatDescription = formatDescriptions.first {
                    let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
                    
                    if let asbd = audioStreamBasicDescription {
                        let sampleRate = Int(asbd.pointee.mSampleRate)
                        let channels = Int(asbd.pointee.mChannelsPerFrame)
                        
                        await MainActor.run {
                            mediaItem.audioSampleRate = sampleRate
                            mediaItem.audioChannels = channels
                        }
                    }
                }
                
                if let estimatedBitrate = try? await audioTrack.load(.estimatedDataRate) {
                    let bitrateKbps = Int(estimatedBitrate / 1000)
                    await MainActor.run {
                        mediaItem.audioBitrate = bitrateKbps
                    }
                }
            }
            
            await MainActor.run {
                mediaItem.status = .pending
            }
        } catch {
            print("Failed to load audio metadata: \(error)")
            await MainActor.run {
                mediaItem.status = .failed
                mediaItem.errorMessage = "Failed to load audio metadata"
            }
        }
    }
    
    private func generateThumbnail(from image: UIImage, size: CGSize = CGSize(width: 80, height: 80)) -> UIImage? {
        let aspectRatio = image.size.width / image.size.height
        let targetAspectRatio = size.width / size.height
        
        var targetSize = size
        if aspectRatio > targetAspectRatio {
            targetSize.height = size.width / aspectRatio
        } else {
            targetSize.width = size.height * aspectRatio
        }
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    private func generateVideoThumbnailOptimized(for item: MediaItem, url: URL) async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        
        // 优化：设置更快的缩略图生成选项
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        
        do {
            let cgImage = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            let thumbnail = UIImage(cgImage: cgImage)
            await MainActor.run {
                item.thumbnailImage = thumbnail
            }
        } catch {
            print("Failed to generate video thumbnail: \(error)")
            // 设置默认视频图标
            await MainActor.run {
                item.thumbnailImage = UIImage(systemName: "video.fill")}
        }
    }
}

#Preview {
    VideoFormatConversionView()
}
