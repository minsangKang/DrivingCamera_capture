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
    
    // MARK: - Starting the camera
    /// Start the camera and begin the stream of data.
    func start() async {
        // Verify that the person authorizes the app to use device cameras and microphones.
        guard await captureService.isAuthorized else {
            status = .unauthorized
            return
        }
        do {
            // Synchronize the state of the model with the persistent state.
            await syncState()
            // Start the capture service to start the flow of data.
            try await captureService.start(with: cameraState)
            observeState()
            status = .running
        } catch {
            logger.error("Failed to start capture service. \(error)")
            status = .failed
        }
    }
    
    /// Synchronizes the persistent camera state.
    ///
    /// `CameraState` represents the persistent state, such as the capture mode, that the app and extension share.
    func syncState() async {
        cameraState = await CameraState.current
        captureMode = cameraState.captureMode
        qualityPrioritization = cameraState.qualityPrioritization
        isLivePhotoEnabled = cameraState.isLivePhotoEnabled
        isHDRVideoEnabled = cameraState.isVideoHDREnabled
    }
    
    // MARK: - Changing modes and devices
    
    /// A value that indicates the mode of capture for the camera.
    var captureMode = CaptureMode.photo {
        didSet {
            guard status == .running else { return }
            Task {
                isSwitchingModes = true
                defer { isSwitchingModes = false }
                // Update the configuration of the capture service for the new mode.
                try? await captureService.setCaptureMode(captureMode)
                // Update the persistent state value.
                cameraState.captureMode = captureMode
            }
        }
    }
    
    /// Selects the next available video device for capture.
    func switchVideoDevices() async {
        isSwitchingVideoDevices = true
        defer { isSwitchingVideoDevices = false }
        await captureService.selectNextVideoDevice()
    }
    
    // MARK: - Photo capture
    
    /// Captures a photo and writes it to the user's Photos library.
    func capturePhoto() async {
        do {
            let photoFeatures = PhotoFeatures(isLivePhotoEnabled: isLivePhotoEnabled, qualityPrioritization: qualityPrioritization)
            let photo = try await captureService.capturePhoto(with: photoFeatures)
            try await mediaLibrary.save(photo: photo)
        } catch {
            self.error = error
        }
    }
    
    /// A Boolean value that indicates whether to capture Live Photos when capturing stills.
    var isLivePhotoEnabled = true {
        didSet {
            // Update the persistent state value.
            cameraState.isLivePhotoEnabled = isLivePhotoEnabled
        }
    }
    
    /// A value that indicates how to balance the photo capture quality versus speed.
    var qualityPrioritization = QualityPrioritization.quality {
        didSet {
            // Update the persistent state value.
            cameraState.qualityPrioritization = qualityPrioritization
        }
    }
    
    /// Performs a focus and expose operation at the specified screen point.
    func focusAndExpose(at point: CGPoint) async {
        await captureService.focusAndExpose(at: point)
    }
    
    /// Sets the `showCaptureFeedback` state to indicate that capture is underway.
    private func flashScreen() {
        shouldFlashScreen = true
        withAnimation(.linear(duration: 0.01)) {
            shouldFlashScreen = false
        }
    }
    
    // MARK: - Video capture
    /// A Boolean value that indicates whether the camera captures video in HDR format.
    var isHDRVideoEnabled = false {
        didSet {
            guard status == .running, captureMode == .video else { return }
            Task {
                await captureService.setHDRVideoEnabled(isHDRVideoEnabled)
                // Update the persistent state value.
                cameraState.isVideoHDREnabled = isHDRVideoEnabled
            }
        }
    }
    
    /// Toggles the state of recording.
    func toggleRecording() async {
        switch await captureService.captureActivity {
        case .movieCapture:
            do {
                // If currently recording, stop the recording and write the movie to the library.
                let movie = try await captureService.stopRecording()
                try await mediaLibrary.save(movie: movie)
            } catch {
                self.error = error
            }
        default:
            // In any other case, start recording.
            await captureService.startRecording()
        }
    }
    
    // MARK: - Internal state observations
    
    // Set up camera's state observations.
    private func observeState() {
        Task {
            // Await new thumbnails that the media library generates when saving a file.
            for await thumbnail in mediaLibrary.thumbnails.compactMap({ $0 }) {
                self.thumbnail = thumbnail
            }
        }
        
        Task {
            // Await new capture activity values from the capture service.
            for await activity in await captureService.$captureActivity.values {
                if activity.willCapture {
                    // Flash the screen to indicate capture is starting.
                    flashScreen()
                } else {
                    // Forward the activity to the UI.
                    captureActivity = activity
                }
            }
        }
        
        Task {
            // Await updates to the capabilities that the capture service advertises.
            for await capabilities in await captureService.$captureCapabilities.values {
                isHDRVideoSupported = capabilities.isHDRSupported
                cameraState.isVideoHDRSupported = capabilities.isHDRSupported
            }
        }
        
        Task {
            // Await updates to a person's interaction with the Camera Control HUD.
            for await isShowingFullscreenControls in await captureService.$isShowingFullscreenControls.values {
                withAnimation {
                    // Prefer showing a minimized UI when capture controls enter a fullscreen appearance.
                    prefersMinimizedUI = isShowingFullscreenControls
                }
            }
        }
    }
}
