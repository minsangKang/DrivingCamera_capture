//
//  CameraView.swift
//  DrivingCamera_capture
//
//  Created by Kang Minsang on 1/28/25.
//

import SwiftUI

struct CameraView: UIViewControllerRepresentable {
    
    @Binding var isRecording: Bool
    @ObservedObject var viewModel: CameraViewModel
    
    class Coordinator {
        var parent: CameraView
        var controller: CameraViewController?
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func startRecording() {
            controller?.startRecording()
        }
        
        func stopRecording() {
            controller?.stopRecording()
        }
    }
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let cameraVC = CameraViewController()
        context.coordinator.controller = cameraVC
        DispatchQueue.main.async {
            self.viewModel.controller = cameraVC
        }
        return cameraVC
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        DispatchQueue.main.async {
            self.viewModel.controller = uiViewController
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
}
