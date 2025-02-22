/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 카메라 뷰에 대한 모델을 나타내는 프로토콜.
 */

import SwiftUI

/// 카메라 뷰에 대한 모델을 나타내는 프로토콜.
///
/// AVFoundation 카메라 API는 물리적 장치에서 실행되어야 합니다.
/// 앱은 프로토콜로 모델을 정의하여 SwiftUI 뷰를 미리 보기 할 때
/// 실제 카메라를 테스트 카메라로 쉽게 교체할 수 있게 만듭니다.
@MainActor
protocol Camera: AnyObject {
    
    /// 카메라의 현재 상태를 제공합니다.
    var status: CameraStatus { get }
    
    /// 카메라의 현재 활동 상태로, 사진 촬영, 동영상 촬영 또는 대기 상태일 수 있습니다.
    var captureActivity: CaptureActivity { get }
    
    /// 카메라 미리 보기의 비디오 콘텐츠 소스입니다.
    var previewSource: PreviewSource { get }
    
    /// 카메라 캡처 파이프라인을 시작합니다.
    func start() async
    
    /// 캡처 모드로, 사진 또는 동영상 모드일 수 있습니다.
    var captureMode: CaptureMode { get set }
    
    /// 카메라가 현재 캡처 모드를 전환 중인지 여부를 나타내는 Boolean 값입니다.
    var isSwitchingModes: Bool { get }
    
    /// 카메라가 최소화된 UI 컨트롤 집합을 표시하는 것을 선호하는지 여부를 나타내는 Boolean 값입니다.
    var prefersMinimizedUI: Bool { get }
    
    /// 호스트 시스템에서 사용 가능한 비디오 장치들 사이를 전환합니다.
    func switchVideoDevices() async
    
    /// 카메라가 현재 비디오 장치를 전환 중인지 여부를 나타내는 Boolean 값입니다.
    var isSwitchingVideoDevices: Bool { get }
    
    /// 한 번의 자동 초점 및 노출 작업을 수행합니다.
    func focusAndExpose(at point: CGPoint) async
    
    /// 스틸을 촬영할 때 Live Photos를 캡처할지 여부를 나타내는 Boolean 값입니다.
    var isLivePhotoEnabled: Bool { get set }
    
    /// 사진 캡처 품질과 속도 사이의 균형을 나타내는 값입니다.
    var qualityPrioritization: QualityPrioritization { get set }
    
    /// 사진을 캡처하고 사용자의 사진 라이브러리에 저장합니다.
    func capturePhoto() async
    
    /// 캡처가 시작될 때 화면에 시각적 피드백을 표시할지 여부를 나타내는 Boolean 값입니다.
    var shouldFlashScreen: Bool { get }
    
    /// 카메라가 HDR 비디오 녹화를 지원하는지 여부를 나타내는 Boolean 값입니다.
    var isHDRVideoSupported: Bool { get }
    
    /// 카메라가 HDR 비디오 녹화를 활성화했는지 여부를 나타내는 Boolean 값입니다.
    var isHDRVideoEnabled: Bool { get set }
    
    /// 동영상 녹화를 시작하거나 중지하고, 완료되면 사용자의 사진 라이브러리에 저장합니다.
    func toggleRecording() async
    
    /// 가장 최근에 캡처된 사진 또는 동영상의 썸네일 이미지입니다.
    var thumbnail: CGImage? { get }
    
    /// 카메라에서 문제가 발생한 경우의 에러입니다.
    var error: Error? { get }
    
    /// 카메라의 상태를 지속된 값과 동기화합니다.
    func syncState() async
}
