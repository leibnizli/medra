//
//  ContentView.swift
//  hummingbird
//
//  Created by admin on 2025/11/4.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            VideoMainView()
                .tabItem {
                    Label("Video", systemImage: "video")
                }
            ImageMainView()
                    .tabItem {
                        Label("Image", systemImage: "photo")
                    }
            AudioMainView()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }
        }
        .environment(\.horizontalSizeClass, .compact)
    }
}

#Preview {
    ContentView()
}
