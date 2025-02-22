/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 카메라 미리보기 주위에 컨테이너 뷰를 제공하는 뷰.
 */

import SwiftUI

// 세로 방향 비율
typealias AspectRatio = CGSize
let photoAspectRatio = AspectRatio(width: 3.0, height: 4.0)
let movieAspectRatio = AspectRatio(width: 9.0, height: 16.0)

/// 카메라 미리보기 주위에 컨테이너 뷰를 제공하는 View.
///
/// 이 View는 캡처 모드 변경이나 장치 전환 시 전환 효과를 적용합니다.
/// 컴팩트 장치 크기에서는 이 View를 사용하여 사진 캡처 모드에서 UI에 더 잘 맞도록 카메라 미리보기의 수직 위치를 조정합니다.
@MainActor
struct PreviewContainer<Content: View, CameraModel: Camera>: View {
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State var camera: CameraModel
    
    // 전환 효과를 위한 상태 값.
    @State private var blurRadius = CGFloat.zero
    
    // 컴팩트 장치 크기에서 사진 캡처 모드일 때, 미리보기 영역을 오프셋만큼 이동시켜서 UI에 더 잘 맞도록 함.
    private let photoModeOffset = CGFloat(-44)
    private let content: Content
    
    init(camera: CameraModel, @ViewBuilder content: () -> Content) {
        self.camera = camera
        self.content = content()
    }
    
    var body: some View {
        // 컴팩트 장치에서 비디오 미리보기 범위 주위에 뷰 파인더 사각형을 표시.
        if horizontalSizeClass == .compact {
            ZStack {
                previewView
            }
            .clipped()
            // 선택된 캡처 모드에 따라 적절한 종횡비를 적용.
            .aspectRatio(aspectRatio, contentMode: .fit)
            // 사진 모드에서는 미리보기 영역의 수직 오프셋을 조정하여 UI에 더 잘 맞도록 함.
            .offset(y: camera.captureMode == .photo ? photoModeOffset : 0)
        } else {
            // 일반 크기 UI에서는 미리보기를 전체 화면에 표시.
            previewView
        }
    }
    
    /// 카메라 미리보기에게 애니메이션을 적용.
    var previewView: some View {
        content
            .blur(radius: blurRadius, opaque: true)
            .onChange(of: camera.isSwitchingModes, updateBlurRadius(_:_:))
            .onChange(of: camera.isSwitchingVideoDevices, updateBlurRadius(_:_:))
    }
    
    func updateBlurRadius(_: Bool, _ isSwitching: Bool) {
        withAnimation {
            blurRadius = isSwitching ? 30 : 0
        }
    }
    
    var aspectRatio: AspectRatio {
        camera.captureMode == .photo ? photoAspectRatio : movieAspectRatio
    }
}
