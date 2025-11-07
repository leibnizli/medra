//
//  SettingsView.swift
//  hummingbird
//
//  设置视图
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: CompressionSettings
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("图片质量")
                            Spacer()
                            Text("\(Int(settings.imageQuality * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.imageQuality, in: 0.1...1.0, step: 0.05)
                    }
                } header: {
                    Text("图片压缩")
                } footer: {
                    Text("质量越高文件越大，保持原始分辨率")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("视频质量")
                            Spacer()
                            Text("\(Int(settings.videoQuality * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.videoQuality, in: 0.1...1.0, step: 0.05)
                    }
                } header: {
                    Text("视频压缩")
                } footer: {
                    Text("质量越高文件越大，保持原始分辨率")
                }
            }
            .navigationTitle("压缩设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
