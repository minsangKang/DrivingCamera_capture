/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 주요 카메라 사용자 인터페이스를 제공하는 뷰.
 */

import SwiftUI
import AVFoundation

/// 주요 카메라 사용자 인터페이스를 제공하는 뷰.
struct CameraUI<CameraModel: Camera>: PlatformView {
    
    @State var camera: CameraModel
    @Binding var swipeDirection: SwipeDirection
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        Group {
            if isRegularSize {
                regularUI
            } else {
                compactUI
            }
        }
        .overlay(alignment: .top) {
            switch camera.captureMode {
            case .photo:
                LiveBadge()
                    .opacity(camera.captureActivity.isLivePhoto ? 1.0 : 0.0)
            case .video:
                RecordingTimeView(time: camera.captureActivity.currentTime)
                    .offset(y: isRegularSize ? 20 : 0)
            }
        }
        .overlay {
            StatusOverlayView(status: camera.status)
        }
    }
    
    /// UI 요소들을 수직으로 배치하는 뷰.
    @ViewBuilder
    var compactUI: some View {
        VStack(spacing: 0) {
            FeaturesToolbar(camera: camera)
            Spacer()
            CaptureModeView(camera: camera, direction: $swipeDirection)
            MainToolbar(camera: camera)
                .padding(.bottom, bottomPadding)
        }
    }
    
    /// UI 요소들을 층별로 쌓는 뷰.
    @ViewBuilder
    var regularUI: some View {
        VStack {
            Spacer()
            ZStack {
                CaptureModeView(camera: camera, direction: $swipeDirection)
                    .offset(x: -250) // 센터에서의 수직 오프셋.
                MainToolbar(camera: camera)
                FeaturesToolbar(camera: camera)
                    .frame(width: 250)
                    .offset(x: 250) // 센터에서의 수직 오프셋.
            }
            .frame(width: 740)
            .background(.ultraThinMaterial.opacity(0.8))
            .cornerRadius(12)
            .padding(.bottom, 32)
        }
    }
    
    var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded {
                // 스와이프 방향 캡처.
                swipeDirection = $0.translation.width < 0 ? .left : .right
            }
    }
    
    var bottomPadding: CGFloat {
        // iOS에서 하단 툴바의 오프셋을 동적으로 계산.
        let bounds = UIScreen.main.bounds
        let rect = AVMakeRect(aspectRatio: movieAspectRatio, insideRect: bounds)
        return (rect.minY.rounded() / 2) + 12
    }
}

#Preview {
    CameraUI(camera: PreviewCameraModel(captureMode: .photo), swipeDirection: .constant(.left))
}
