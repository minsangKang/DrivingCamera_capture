/*
이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.

개요:
AVFoundation 캡처 API를 사용하여 미디어 캡처를 수행하는 방법을 보여주는 샘플 앱입니다.
*/

import os
import SwiftUI

@main
/// The AVCam app's main entry point.
struct AVCamApp: App {

    // Simulator doesn't support the AVFoundation capture APIs. Use the preview camera when running in Simulator.
    @State private var camera = CameraModel()
    
    // An indication of the scene's operational state.
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            CameraView(camera: camera)
                .statusBarHidden(true)
                .task {
                    // Start the capture pipeline.
                    await camera.start()
                }
                // Monitor the scene phase. Synchronize the persistent state when
                // the camera is running and the app becomes active.
                .onChange(of: scenePhase) { _, newPhase in
                    guard camera.status == .running, newPhase == .active else { return }
                    Task { @MainActor in
                        await camera.syncState()
                    }
                }
        }
    }
}

/// A global logger for the app.
let logger = Logger()
