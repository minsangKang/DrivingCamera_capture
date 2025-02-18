/*
이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.

개요:
AVFoundation 캡처 API를 사용하여 미디어 캡처를 수행하는 방법을 보여주는 샘플 앱입니다.
*/

import os
import SwiftUI

@main
/// AVCam 앱의 진입점
struct AVCamApp: App {

    // 시뮬레이터에서는 AVFoundation 캡처 API를 지원하지 않습니다.
    // 시뮬레이터에서 실행할 때는 미리보기 카메라를 사용하세요.
    @State private var camera = CameraModel()
    
    // scene의 동작 상태를 나타내는 환경 변수.
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            CameraView(camera: camera)
                .statusBarHidden(true)
                .task {
                    // 캡처 파이프라인을 시작합니다.
                    await camera.start()
                }
                // scene 상태 변화를 감지합니다.
                // 카메라가 실행 중이고 앱이 활성화되면 지속 상태를 동기화합니다.
                .onChange(of: scenePhase) { _, newPhase in
                    guard camera.status == .running, newPhase == .active else { return }
                    Task { @MainActor in
                        await camera.syncState()
                    }
                }
        }
    }
}

///  앱에서 사용할 전역 로거.
let logger = Logger()
