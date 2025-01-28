//
//  CameraViewController.swift
//  DrivingCamera_capture
//
//  Created by Kang Minsang on 1/28/25.
//

import UIKit
import AVFoundation

class CameraViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var videoOutput: AVCaptureMovieFileOutput?
    var outputURL: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupCamera()
    }
}

// MARK: - Functions

extension CameraViewController {
    private func setupCamera() {
        // captureSession 생성
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
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
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = self.view.layer.bounds
        self.view.layer.addSublayer(previewLayer)
        
        videoPreviewLayer = previewLayer
        captureSession.startRunning()
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
