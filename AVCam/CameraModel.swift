/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 카메라 기능에 대한 인터페이스를 제공하는 객체.
 */

import SwiftUI
import Combine

/// 카메라 기능에 대한 인터페이스를 제공하는 객체.
///
/// 이 객체는 `Camera` 프로토콜의 기본 구현을 제공하며, 카메라 하드웨어를 설정하고 미디어를 캡처하는
/// 인터페이스를 정의합니다. `CameraModel` 자체적으로 캡처를 수행하지 않으며, `@Observable` 타입으로서
/// 앱의 SwiftUI 뷰와 `CaptureService` 간의 상호작용을 중재합니다.
///
/// SwiftUI 미리보기 및 시뮬레이터에서는 `PreviewCameraModel`을 대신 사용합니다.
@Observable
final class CameraModel: Camera {
    
    /// 카메라의 현재 상태(예: unauthorized, running, failed)를 나타냅니다.
    private(set) var status = CameraStatus.unknown
    
    /// 사진 또는 동영상 캡처의 현재 상태를 나타냅니다.
    private(set) var captureActivity = CaptureActivity.idle
    
    /// 앱이 현재 비디오 장치를 전환 중인지 여부를 나타내는 Boolean 값입니다.
    private(set) var isSwitchingVideoDevices = false
    
    /// 카메라가 최소화된 UI 컨트롤 세트를 선호하는지 여부를 나타내는 Boolean 값입니다.
    private(set) var prefersMinimizedUI = false
    
    /// 앱이 현재 촬영 모드를 전환 중인지 여부를 나타내는 Boolean 값입니다.
    private(set) var isSwitchingModes = false
    
    /// 촬영이 시작될 때 시각적 피드백을 표시할지 여부를 나타내는 Boolean 값입니다.
    private(set) var shouldFlashScreen = false
    
    /// 마지막으로 촬영된 사진 또는 동영상의 썸네일 이미지입니다.
    private(set) var thumbnail: CGImage?
    
    /// 사진 또는 동영상 캡처 중 발생한 오류의 세부 정보를 포함하는 에러 객체입니다.
    private(set) var error: Error?
    
    /// 캡처 세션과 비디오 미리보기 레이어 간의 연결을 제공하는 객체입니다.
    var previewSource: PreviewSource { captureService.previewSource }
    
    /// 카메라가 HDR 비디오 녹화를 지원하는지 여부를 나타내는 Boolean 값입니다.
    private(set) var isHDRVideoSupported = false
    
    /// 촬영한 미디어를 사용자의 사진 보관함(Photos 라이브러리)에 저장하는 객체입니다.
    private let mediaLibrary = MediaLibrary()
    
    /// 앱의 촬영 기능을 관리하는 객체입니다.
    private let captureService = CaptureService()
    
    /// 앱과 캡처 확장(capture extension) 간에 공유되는 지속 상태(persistent state)입니다.
    private var cameraState = CameraState()
    
    init() {
        //
    }
    
    // MARK: - 카메라 시작
    
    /// 카메라를 시작하고 데이터 스트림을 시작합니다.
    func start() async {
        // 사용자가 앱에 장치의 카메라 및 마이크 사용을 허용했는지 확인합니다.
        guard await captureService.isAuthorized else {
            status = .unauthorized
            return
        }
        do {
            // 모델의 상태를 지속 상태(persistent state)와 동기화합니다.
            await syncState()
            // 캡처 서비스를 시작하여 데이터 스트림을 시작합니다.
            try await captureService.start(with: cameraState)
            observeState()
            status = .running
        } catch {
            logger.error("🚨 캡처 서비스 시작 실패: \(error)")
            status = .failed
        }
    }
    
    /// 지속적인 카메라 상태를 동기화합니다.
    ///
    /// `CameraState`는 앱과 확장(extension)에서 공유하는 캡처 모드와 같은 지속적인 상태를 나타냅니다.
    func syncState() async {
        cameraState = await CameraState.current
        captureMode = cameraState.captureMode
        qualityPrioritization = cameraState.qualityPrioritization
        isLivePhotoEnabled = cameraState.isLivePhotoEnabled
        isHDRVideoEnabled = cameraState.isVideoHDREnabled
    }
    
    // MARK: - 모드 및 장치 변경
    
    /// 카메라의 캡처 모드를 나타내는 값입니다.
    var captureMode = CaptureMode.photo {
        didSet {
            guard status == .running else { return }
            Task {
                isSwitchingModes = true
                defer { isSwitchingModes = false }
                // 새로운 모드에 맞게 캡처 서비스의 설정을 업데이트합니다.
                try? await captureService.setCaptureMode(captureMode)
                // 지속 상태(persistent state) 값을 업데이트합니다.
                cameraState.captureMode = captureMode
            }
        }
    }
    
    /// 사용 가능한 다음 비디오 장치를 선택하여 캡처 장치를 전환합니다.
    func switchVideoDevices() async {
        isSwitchingVideoDevices = true
        defer { isSwitchingVideoDevices = false }
        await captureService.selectNextVideoDevice()
    }
    
    // MARK: - 사진 촬영
    
    /// 사진을 촬영하고 사용자의 사진 보관함(Photos 라이브러리)에 저장합니다.
    func capturePhoto() async {
        do {
            let photoFeatures = PhotoFeatures(isLivePhotoEnabled: isLivePhotoEnabled, qualityPrioritization: qualityPrioritization)
            let photo = try await captureService.capturePhoto(with: photoFeatures)
            try await mediaLibrary.save(photo: photo)
        } catch {
            self.error = error
        }
    }
    
    /// 정지 사진 촬영 시 Live Photo를 캡처할지 여부를 나타내는 Boolean 값입니다.
    var isLivePhotoEnabled = true {
        didSet {
            // 지속 상태 값을 업데이트합니다.
            cameraState.isLivePhotoEnabled = isLivePhotoEnabled
        }
    }
    
    /// 사진 촬영 품질과 속도의 균형을 설정하는 값을 나타냅니다.
    var qualityPrioritization = QualityPrioritization.quality {
        didSet {
            // 지속 상태(persistent state) 값을 업데이트합니다.
            cameraState.qualityPrioritization = qualityPrioritization
        }
    }
    
    /// 지정된 화면 지점에서 초점 및 노출을 조정하는 작업을 수행합니다.
    func focusAndExpose(at point: CGPoint) async {
        await captureService.focusAndExpose(at: point)
    }
    
    /// 촬영 중임을 나타내도록 `showCaptureFeedback` 상태를 설정합니다.
    private func flashScreen() {
        shouldFlashScreen = true
        withAnimation(.linear(duration: 0.01)) {
            shouldFlashScreen = false
        }
    }
    
    // MARK: - 비디오 촬영
    
    /// 카메라가 HDR 형식으로 비디오를 촬영할지 여부를 나타내는 Boolean 값입니다.
    var isHDRVideoEnabled = false {
        didSet {
            guard status == .running, captureMode == .video else { return }
            Task {
                await captureService.setHDRVideoEnabled(isHDRVideoEnabled)
                // 지속 상태(persistent state) 값을 업데이트합니다.
                cameraState.isVideoHDREnabled = isHDRVideoEnabled
            }
        }
    }
    
    /// 녹화 상태를 전환합니다.
    func toggleRecording() async {
        switch await captureService.captureActivity {
        case .movieCapture:
            do {
                // 현재 녹화 중이면 녹화를 중지하고 동영상을 라이브러리에 저장합니다.
                let movie = try await captureService.stopRecording()
                try await mediaLibrary.save(movie: movie)
            } catch {
                self.error = error
            }
        default:
            // 그 외의 경우에는 녹화를 시작합니다.
            await captureService.startRecording()
        }
    }
    
    // MARK: - 내부 상태 관찰
    
    /// 카메라의 상태를 관찰하도록 설정합니다.
    private func observeState() {
        Task {
            // 미디어 라이브러리가 파일을 저장할 때 생성하는 새 썸네일을 대기합니다.
            for await thumbnail in mediaLibrary.thumbnails.compactMap({ $0 }) {
                self.thumbnail = thumbnail
            }
        }
        
        Task {
            // 캡처 서비스에서 전달하는 새로운 캡처 활동 상태를 대기합니다.
            for await activity in await captureService.$captureActivity.values {
                if activity.willCapture {
                    // 촬영이 시작됨을 알리기 위해 화면을 깜빡입니다.
                    flashScreen()
                } else {
                    // 캡처 상태를 UI에 반영합니다.
                    captureActivity = activity
                }
            }
        }
        
        Task {
            // 캡처 서비스에서 제공하는 기능 업데이트를 대기합니다.
            for await capabilities in await captureService.$captureCapabilities.values {
                isHDRVideoSupported = capabilities.isHDRSupported
                cameraState.isVideoHDRSupported = capabilities.isHDRSupported
            }
        }
        
        Task {
            // 사용자가 카메라 컨트롤 HUD와 상호작용하는 상태 업데이트를 대기합니다.
            for await isShowingFullscreenControls in await captureService.$isShowingFullscreenControls.values {
                withAnimation {
                    // 캡처 컨트롤이 전체 화면 모드로 전환되면 UI를 최소화하도록 설정합니다.
                    prefersMinimizedUI = isShowingFullscreenControls
                }
            }
        }
    }
    
}
