//
//  CompressionView.swift
//  hummingbird
//
//  压缩视图
//

import SwiftUI
import PhotosUI
import AVFoundation
import Photos

struct CompressionView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var mediaItems: [MediaItem] = []
    @State private var isCompressing = false
    @State private var showingSettings = false
    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @StateObject private var settings = CompressionSettings()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部选择按钮
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // 左侧：下拉菜单选择来源
                        Menu {
                            Button(action: { showingPhotoPicker = true }) {
                                Label("从相册选择", systemImage: "photo.on.rectangle.angled")
                            }
                            
                            Button(action: { showingFilePicker = true }) {
                                Label("从文件选择", systemImage: "folder.fill")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("添加文件")
                                    .font(.system(size: 15, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        
                        // 右侧：开始按钮
                        Button(action: startBatchCompression) {
                            HStack(spacing: 6) {
                                if isCompressing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                Text(isCompressing ? "处理中" : "开始压缩")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(mediaItems.isEmpty || isCompressing ? .gray : .green)
                        .disabled(mediaItems.isEmpty || isCompressing)
                        .animation(.easeInOut(duration: 0.2), value: isCompressing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemGroupedBackground))
                    
                    // 底部分隔线
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.5))
                        .frame(height: 0.5)
                }

                
                // 文件列表
                if mediaItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("选择图片或视频开始压缩")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(mediaItems) { item in
                            CompressionItemRow(item: item)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.visible)
                        }
                        .onDelete { indexSet in
                            withAnimation {
                                mediaItems.remove(atOffsets: indexSet)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("媒体压缩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { 
                await loadSelectedItems(newItems)
                await MainActor.run {
                    selectedItems = []
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos]))
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: true
        ) { result in
            Task {
                do {
                    let urls = try result.get()
                    await loadFileURLs(urls)
                } catch {
                    print("文件选择错误: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func loadFileURLs(_ urls: [URL]) async {
        for url in urls {
            // 验证文件是否可访问
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // 检查文件类型
            let isVideo = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
            let mediaItem = MediaItem(pickerItem: nil, isVideo: isVideo)
            
            // 添加到列表
            await MainActor.run {
                mediaItems.append(mediaItem)
            }
            
            do {
                // 读取文件数据
                let data = try Data(contentsOf: url)
                
                await MainActor.run {
                    mediaItem.originalData = data
                    mediaItem.originalSize = data.count
                    mediaItem.fileExtension = url.pathExtension.lowercased()
                    
                    // 设置格式
                    if isVideo {
                        mediaItem.outputVideoFormat = url.pathExtension.lowercased()
                    } else if let type = UTType(filenameExtension: url.pathExtension) {
                        if type.conforms(to: .png) {
                            mediaItem.originalImageFormat = .png
                        } else if type.conforms(to: .heic) {
                            mediaItem.originalImageFormat = .heic
                        } else if type.conforms(to: .webP) {
                            mediaItem.originalImageFormat = .webp
                        } else {
                            mediaItem.originalImageFormat = .jpeg
                        }
                    }
                    
                    // 如果是图片，生成缩略图和获取分辨率
                    if !isVideo, let image = UIImage(data: data) {
                        mediaItem.thumbnailImage = generateThumbnail(from: image)
                        mediaItem.originalResolution = image.size
                        mediaItem.status = .pending
                    }
                }
                
                // 如果是视频，处理视频相关信息
                if isVideo {
                    // 创建临时文件
                    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent("source_\(mediaItem.id.uuidString)")
                        .appendingPathExtension(url.pathExtension)
                    try data.write(to: tempURL)
                    
                    await MainActor.run {
                        mediaItem.sourceVideoURL = tempURL
                    }
                    
                    // 加载视频元数据
                    await loadVideoMetadata(for: mediaItem, url: tempURL)
                }
            } catch {
                await MainActor.run {
                    mediaItem.status = .failed
                    mediaItem.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loadSelectedItems(_ items: [PhotosPickerItem]) async {
        mediaItems.removeAll()
        
        for item in items {
            let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) })
            let mediaItem = MediaItem(pickerItem: item, isVideo: isVideo)
            
            // 先添加到列表，显示加载状态
            await MainActor.run {
                mediaItems.append(mediaItem)
            }
            
            if isVideo {
                // 视频优化：延迟加载，只在需要时加载完整数据
                await loadVideoItemOptimized(item, mediaItem)
            } else {
                // 图片：正常加载
                await loadImageItem(item, mediaItem)
            }
        }
    }
    
    private func loadImageItem(_ item: PhotosPickerItem, _ mediaItem: MediaItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            await MainActor.run {
                mediaItem.originalData = data
                mediaItem.originalSize = data.count
                
                // 检测原始图片格式
                let isPNG = item.supportedContentTypes.contains { contentType in
                    contentType.identifier == "public.png" ||
                    contentType.conforms(to: .png)
                }
                let isHEIC = item.supportedContentTypes.contains { contentType in
                    contentType.identifier == "public.heic" || 
                    contentType.identifier == "public.heif" ||
                    contentType.conforms(to: .heic) ||
                    contentType.conforms(to: .heif)
                }
                let isWebP = item.supportedContentTypes.contains { contentType in
                    contentType.identifier == "org.webmproject.webp" ||
                    contentType.preferredMIMEType == "image/webp"
                }
                
                if isPNG {
                    mediaItem.originalImageFormat = .png
                    mediaItem.fileExtension = "png"
                } else if isHEIC {
                    mediaItem.originalImageFormat = .heic
                    mediaItem.fileExtension = "heic"
                } else if isWebP {
                    mediaItem.originalImageFormat = .webp
                    mediaItem.fileExtension = "webp"
                } else {
                    mediaItem.originalImageFormat = .jpeg
                    mediaItem.fileExtension = "jpg"
                }
                
                if let image = UIImage(data: data) {
                    mediaItem.thumbnailImage = generateThumbnail(from: image)
                    mediaItem.originalResolution = image.size
                }
                
                // 加载完成，设置为等待状态
                mediaItem.status = .pending
            }
        }
    }
    
    private func loadVideoItemOptimized(_ item: PhotosPickerItem, _ mediaItem: MediaItem) async {
        // 检测视频格式
        var detectedFormat = "video"
        
        // 检查所有支持的内容类型
        for contentType in item.supportedContentTypes {
            // MOV 格式检测
            if contentType.identifier == "com.apple.quicktime-movie" ||
               contentType.conforms(to: .quickTimeMovie) ||
               contentType.preferredFilenameExtension == "mov" {
                detectedFormat = "mov"
                break
            }
            // MP4 格式检测
            else if contentType.identifier == "public.mpeg-4" ||
                    contentType.conforms(to: .mpeg4Movie) ||
                    contentType.preferredFilenameExtension == "mp4" ||
                    contentType.identifier == "public.mp4" {
                detectedFormat = "mp4"
                break
            }
            // AVI 格式检测
            else if contentType.identifier == "public.avi" ||
                    contentType.preferredFilenameExtension == "avi" {
                detectedFormat = "avi"
                break
            }
            // MKV 格式检测
            else if contentType.identifier == "org.matroska.mkv" ||
                    contentType.preferredFilenameExtension == "mkv" {
                detectedFormat = "mkv"
                break
            }
            // WebM 格式检测
            else if contentType.identifier == "org.webmproject.webm" ||
                    contentType.preferredFilenameExtension == "webm" {
                detectedFormat = "webm"
                break
            }
            // 通用视频格式检测
            else if contentType.conforms(to: .movie) ||
                    contentType.conforms(to: .video) {
                // 尝试从 preferredFilenameExtension 获取具体格式
                if let ext = contentType.preferredFilenameExtension?.lowercased(),
                   ["mov", "mp4", "avi", "mkv", "webm", "m4v"].contains(ext) {
                    detectedFormat = ext
                    break
                }
            }
        }
        
        await MainActor.run {
            // 设置文件扩展名
            mediaItem.fileExtension = detectedFormat
            // 同时记录原始视频格式，用于后续格式转换的显示
            if detectedFormat != "video" {
                mediaItem.outputVideoFormat = detectedFormat
            }
        }
        
        // 优化：使用 URL 方式加载视频，避免将整个文件加载到内存
        if let url = try? await item.loadTransferable(type: URL.self) {
            await MainActor.run {
                mediaItem.sourceVideoURL = url
                
                // 快速获取文件大小（不加载整个文件）
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                    mediaItem.originalSize = fileSize
                }
                
                // 异步获取视频信息和缩略图
                Task {
                    await loadVideoMetadata(for: mediaItem, url: url)
                }
            }
        } else {
            // 回退到数据加载方式（兼容性）
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    mediaItem.originalData = data
                    mediaItem.originalSize = data.count
                    
                    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent("source_\(mediaItem.id.uuidString)")
                        .appendingPathExtension("mov")
                    try? data.write(to: tempURL)
                    mediaItem.sourceVideoURL = tempURL
                    
                    Task {
                        await loadVideoMetadata(for: mediaItem, url: tempURL)
                    }
                }
            }
        }
    }
    
    private func loadVideoMetadata(for mediaItem: MediaItem, url: URL) async {
        let asset = AVURLAsset(url: url)
        
        // 异步加载视频轨道信息和时长
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let videoTrack = tracks.first {
                let size = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let isPortrait = abs(transform.b) == 1.0 || abs(transform.c) == 1.0
                
                await MainActor.run {
                    mediaItem.originalResolution = isPortrait ? CGSize(width: size.height, height: size.width) : size
                }
            }
            
            // 加载视频时长
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            await MainActor.run {
                mediaItem.duration = durationSeconds
            }
        } catch {
            print("加载视频轨道信息失败: \(error)")
        }
        
        // 异步生成缩略图
        await generateVideoThumbnailOptimized(for: mediaItem, url: url)
        
        // 视频元数据加载完成，设置为等待状态
        await MainActor.run {
            mediaItem.status = .pending
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
            print("生成视频缩略图失败: \(error)")
            // 设置默认视频图标
            await MainActor.run {
                item.thumbnailImage = UIImage(systemName: "video.fill")
            }
        }
    }
    
    private func startBatchCompression() {
        isCompressing = true
        Task {
            // 重置所有项目状态，以便重新压缩
            await MainActor.run {
                for item in mediaItems {
                    item.status = .pending
                    item.progress = 0
                    item.compressedData = nil
                    item.compressedSize = 0
                    item.compressedResolution = nil
                    item.compressedVideoURL = nil
                    item.usedBitrate = nil
                    item.errorMessage = nil
                }
            }
            
            for item in mediaItems {
                await compressItem(item)
            }
            await MainActor.run {
                isCompressing = false
            }
        }
    }
    
    private func compressItem(_ item: MediaItem) async {
        await MainActor.run {
            item.status = .compressing
            item.progress = 0
        }
        
        if item.isVideo {
            await compressVideo(item)
        } else {
            await compressImage(item)
        }
    }
    
    private func compressImage(_ item: MediaItem) async {
        guard let originalData = item.originalData else {
            await MainActor.run {
                item.status = .failed
                item.errorMessage = "无法加载原始图片"
            }
            return
        }
        
        // 显示压缩开始状态
        await MainActor.run {
            item.status = .compressing
            item.progress = 0.1
        }
        
        // 短暂延迟，让用户看到"压缩中"状态
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        
        do {
            // 更新进度：准备压缩
            await MainActor.run {
                item.progress = 0.3
            }
            
            // 根据设置决定输出格式
            let outputFormat: ImageFormat
            if item.originalImageFormat == .png {
                // PNG 始终保持 PNG 格式
                outputFormat = .png
            } else if item.originalImageFormat == .webp {
                // WebP 始终保持 WebP 格式
                outputFormat = .webp
            } else if settings.preferHEIC && item.originalImageFormat == .heic {
                // 开启 HEIC 优先，且原图是 HEIC，保持 HEIC
                outputFormat = .heic
            } else {
                // 否则使用 JPEG (MozJPEG)
                outputFormat = .jpeg
            }
            
            // 更新进度：正在压缩
            await MainActor.run {
                item.progress = 0.5
            }
            
            let compressed = try await MediaCompressor.compressImage(
                originalData,
                settings: settings,
                preferredFormat: outputFormat,
                progressHandler: { progress in
                    Task { @MainActor in
                        // 将压缩进度映射到 0.5-0.9 范围
                        item.progress = 0.5 + (progress * 0.4)
                    }
                }
            )
            
            // 更新进度：压缩完成，处理结果
            await MainActor.run {
                item.progress = 0.9
            }
            
            await MainActor.run {
                // 智能判断：如果压缩后反而变大，保留原图
                if compressed.count >= originalData.count {
                    print("⚠️ [压缩判断] 压缩后大小 (\(compressed.count) bytes) >= 原图 (\(originalData.count) bytes)，保留原图")
                    item.compressedData = originalData
                    item.compressedSize = originalData.count
                    item.outputImageFormat = item.originalImageFormat  // 保持原格式
                } else {
                    print("✅ [压缩判断] 压缩成功，从 \(originalData.count) bytes 减少到 \(compressed.count) bytes")
                    item.compressedData = compressed
                    item.compressedSize = compressed.count
                    item.outputImageFormat = outputFormat  // 使用压缩后的格式
                }
                
                if let image = UIImage(data: item.compressedData!) {
                    item.compressedResolution = image.size
                }
                item.status = .completed
                item.progress = 1.0
            }
        } catch {
            await MainActor.run {
                item.status = .failed
                item.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func compressVideo(_ item: MediaItem) async {
        // 确保有视频 URL
        guard let sourceURL = item.sourceVideoURL else {
            await MainActor.run {
                item.status = .failed
                item.errorMessage = "无法加载原始视频"
            }
            return
        }
        
        // 如果需要完整数据但还没有加载，现在加载
        if item.originalData == nil {
            await item.loadVideoDataIfNeeded()
        }
        
        // 使用 FFmpeg 压缩，不需要 continuation（FFmpeg 是异步回调）
        MediaCompressor.compressVideo(
            at: sourceURL,
            settings: settings,
            outputFileType: .mp4,
            progressHandler: { progress in
                Task { @MainActor in
                    item.progress = progress
                }
            },
            completion: { result in
                Task { @MainActor in
                    switch result {
                    case .success(let url):
                        // 获取压缩后的文件大小
                        let compressedSize: Int
                        if let data = try? Data(contentsOf: url) {
                            compressedSize = data.count
                        } else {
                            compressedSize = 0
                        }
                        
                        // 智能判断：如果压缩后反而变大，保留原视频
                        if compressedSize >= item.originalSize {
                            print("⚠️ [视频压缩判断] 压缩后大小 (\(compressedSize) bytes) >= 原视频 (\(item.originalSize) bytes)，保留原视频")
                            
                            // 使用原视频
                            item.compressedVideoURL = sourceURL
                            item.compressedSize = item.originalSize
                            item.compressedResolution = item.originalResolution
                            
                            // 清理压缩后的临时文件
                            try? FileManager.default.removeItem(at: url)
                        } else {
                            print("✅ [视频压缩判断] 压缩成功，从 \(item.originalSize) bytes 减少到 \(compressedSize) bytes")
                            
                            // 使用压缩后的视频
                            item.compressedVideoURL = url
                            item.compressedSize = compressedSize
                            
                            let asset = AVURLAsset(url: url)
                            if let videoTrack = asset.tracks(withMediaType: .video).first {
                                let size = videoTrack.naturalSize
                                let transform = videoTrack.preferredTransform
                                let isPortrait = abs(transform.b) == 1.0 || abs(transform.c) == 1.0
                                item.compressedResolution = isPortrait ? CGSize(width: size.height, height: size.width) : size
                            }
                        }
                        
                        // 使用原始分辨率计算比特率（从 item.originalResolution）
                        if let originalResolution = item.originalResolution {
                            let bitrateBps = settings.calculateBitrate(for: originalResolution)
                            item.usedBitrate = Double(bitrateBps) / 1_000_000.0 // 转换为 Mbps
                            print("✅ 设置比特率: \(item.usedBitrate ?? 0) Mbps (分辨率: \(originalResolution))")
                        }
                        
                        item.status = .completed
                        item.progress = 1.0
                    case .failure(let error):
                        item.status = .failed
                        item.errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }
}

#Preview {
    CompressionView()
}
