//
//  ContentView.swift
//  DrivingCamera_capture
//
//  Created by Kang Minsang on 1/28/25.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - UIKit 기반 카메라 뷰컨트롤러

class CameraViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput) else { return }
        
        captureSession.addInput(videoInput)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        view.layer.addSublayer(previewLayer)
        
        videoPreviewLayer = previewLayer
        captureSession.startRunning()
    }
}

// MARK: - SwiftUI에서 사용하기 위한 UIViewControllerRepresentable

struct CameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

// MARK: - SwiftUI 메인 화면

struct ContentView: View {
    var body: some View {
        VStack {
            CameraView()
                .edgesIgnoringSafeArea(.all)
            Button("Start Recording") {
                // 녹화 기능 추가 예정
            }
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
    }
}

#Preview {
    ContentView()
}
