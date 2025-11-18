//
//  MainView.swift
//  hummingbird
//
//  Created by admin on 2025/11/18.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: CompressionMainView()) {
                    HStack(spacing: 16) {
                        Image(systemName: "bolt.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Compression")
                                .font(.headline)
                            Text("Compress images, videos and audio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                NavigationLink(destination: ResolutionView()) {
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.title2)
                            .foregroundStyle(.green)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resolution")
                                .font(.headline)
                            Text("Adjust image and video resolution")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                NavigationLink(destination: FormatMainView()) {
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Format Conversion")
                                .font(.headline)
                            Text("Convert between different formats")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Hummingbird")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    MainView()
}
