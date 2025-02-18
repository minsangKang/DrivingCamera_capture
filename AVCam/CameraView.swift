/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 샘플 앱의 주요 사용자 인터페이스.
 */

import SwiftUI
import AVFoundation
import AVKit

@MainActor
struct CameraView<CameraModel: Camera>: PlatformView {
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State var camera: CameraModel
    
    // 사용자가 카메라 미리보기 또는 모드 서낵기에서 스와이프하는 방향.
    @State var swipeDirection = SwipeDirection.left
    
    var body: some View {
        ZStack {
            // 미리보기 배치를 관리하는 컨테이너 뷰.
            PreviewContainer(camera: camera) {
                // 캡처된 콘텐츠의 미리보기를 제공하는 뷰.
                CameraPreview(source: camera.previewSource)
                // 기기 하드웨어 버튼을 통한 캡처 이벤트 처리.
                    .onCameraCaptureEvent { event in
                        if event.phase == .ended {
                            Task {
                                switch camera.captureMode {
                                case .photo:
                                    // 하드웨어 버튼을 눌러 사진을 캡처.
                                    await camera.capturePhoto()
                                case .video:
                                    // 하드웨어 버튼을 눌러 비디오 녹화를 전환.
                                    await camera.toggleRecording()
                                }
                            }
                        }
                    }
                // 탭한 위치에 초점과 노출을 맞춤.
                    .onTapGesture { location in
                        Task { await camera.focusAndExpose(at: location) }
                    }
                // 왼쪽 또는 오른쪽으로 스와이프하여 캡처 모드 전환.
                    .simultaneousGesture(swipeGesture)
                /// `shouldFlashScreen` 값이 캡처 시작 시 잠깐 `true`로 변경된 후 즉시 `false`로 돌아갑니다.
                /// 이 변경을 사용하여 사진을 캡처할 때 화면을 깜빡이게 하여 시각적 피드백을 제공합니다.
                    .opacity(camera.shouldFlashScreen ? 0 : 1)
            }
            // 주요 카메라 UI.
            CameraUI(camera: camera, swipeDirection: $swipeDirection)
        }
    }
    
    var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded {
                // 스와이프 방향 감지.
                swipeDirection = $0.translation.width < 0 ? .left : .right
            }
    }
}

#Preview {
    CameraView(camera: PreviewCameraModel())
}

enum SwipeDirection {
    case left
    case right
    case up
    case down
}
