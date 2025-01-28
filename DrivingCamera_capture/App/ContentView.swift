//
//  ContentView.swift
//  DrivingCamera_capture
//
//  Created by Kang Minsang on 1/28/25.
//

import SwiftUI
import AVFoundation
import UIKit

struct ContentView: View {
    @State private var isRecording = false
    @StateObject private var viewModel = CameraViewModel()
    
    var body: some View {
        VStack {
            CameraView(isRecording: $isRecording, viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            HStack {
                Button(isRecording ? "Stop Recording" : "Start Recording") {
                    if isRecording {
                        viewModel.controller?.stopRecording()
                    } else {
                        viewModel.controller?.startRecording()
                    }
                    isRecording.toggle()
                }
                .padding()
                .background(isRecording ? Color.blue : Color.red)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
