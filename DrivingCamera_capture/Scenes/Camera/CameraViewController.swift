//
//  CameraViewController.swift
//  DrivingCamera_capture
//
//  Created by Kang Minsang on 1/28/25.
//

import UIKit
import AVFoundation

import SnapKit
import Then

final class CameraViewController: UIViewController {
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var outputURL: URL?
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.setupCamera()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.view.layer.sublayers?.removeAll()
    }
}

// MARK: - Functions

extension CameraViewController {
    private func setupCamera() {
        // captureSession 생성
        let captureSession = AVCaptureSession()
        self.captureSession = captureSession
        
        // captureDevice 생성
        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("[Error] videoCaptureDevice 생성 실패")
            return
        }
        guard let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio) else {
            print("[Error] autioCaptureDevice 생성 실패")
            return
        }
        
        // captureDeviceInput 생성
        do {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .hd4K3840x2160
            
            // video
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            // audio
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
            
            // output
            let videoOutput = AVCaptureMovieFileOutput()
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            self.videoOutput = videoOutput
            
            captureSession.commitConfiguration()
        } catch {
            print("[Error] captureDeviceInput 생성 실패: \(error.localizedDescription)")
        }
        
        // captureVideoPreviewLayer 생성
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.frame = self.view.layer.bounds
        self.view.layer.addSublayer(previewLayer)
        
        self.videoPreviewLayer = previewLayer
        DispatchQueue.global(qos: .background).async {
            captureSession.startRunning()
        }
    }
    
    public func startRecording() {
        let tempURL = tempURL()
        self.outputURL = tempURL
        self.videoOutput?.startRecording(to: tempURL, recordingDelegate: self)
        print("🎥 녹화 시작: \(outputURL!.path)")
    }
    
    public func stopRecording() {
        if self.videoOutput?.isRecording == true {
            self.videoOutput?.stopRecording()
            print("🛑 녹화 중지")
        }
    }
    
    private func tempURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mov"
        return tempDir.appendingPathComponent(fileName)
    }
    
    // 현재 디바이스 방향을 기반으로 회전 각도 반환
    func currentRotationAngle() -> CGFloat {
        switch UIDevice.current.orientation {
        case .portrait:
            return 0
        case .portraitUpsideDown:
            return 180
        case .landscapeLeft:
            return 90
        case .landscapeRight:
            return 270
        default:
            return 0  // 기본값
        }
    }
    
    // 현재 디바이스 방향을 AVCaptureVideoOrientation으로 변환하는 함수
    func currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait  // 기본값
        }
    }
}

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        if (error != nil) {
            print("Error recording movie: \(error!.localizedDescription)")
        } else {
            let videoRecorded = outputURL! as URL
            UISaveVideoAtPathToSavedPhotosAlbum(videoRecorded.path, nil, nil, nil)
        }
    }
}
