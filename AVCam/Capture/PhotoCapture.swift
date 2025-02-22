/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 사진 촬영을 수행하는 객체로, 사진 캡처 출력을 관리합니다.
 */

import AVFoundation
import CoreImage

enum PhotoCaptureError: Error {
    case noPhotoData
}

/// 사진 캡처 출력을 관리하여 사진을 촬영하는 객체.
final class PhotoCapture: OutputService {
    
    /// 현재 사진 캡처 상태를 나타내는 값.
    @Published private(set) var captureActivity: CaptureActivity = .idle
    
    /// 이 서비스의 캡처 출력 유형.
    let output = AVCapturePhotoOutput()
    
    // 출력에 대한 내부 별칭.
    private var photoOutput: AVCapturePhotoOutput { output }
    
    // 현재 사용 가능한 기능들.
    private(set) var capabilities: CaptureCapabilities = .unknown
    
    // 현재 진행 중인 Live Photo 캡처의 수.
    private var livePhotoCount = 0
    
    // MARK: - 사진 캡처.
    
    /// 사용자가 사진 캡처 버튼을 누르면 호출되는 메서드.
    func capturePhoto(with features: PhotoFeatures) async throws -> Photo {
        // delegate 기반 캡처 API를 비동기 컨텍스트에서 사용하기 위해 continuation으로 래핑합니다.
        try await withCheckedThrowingContinuation { continuation in
            
            // 사진 캡처를 구성하는 설정 객체 생성.
            let photoSettings = createPhotoSettings(with: features)
            
            let delegate = PhotoCaptureDelegate(continuation: continuation)
            monitorProgress(of: delegate)
            
            // 지정된 설정으로 새 사진을 캡처합니다.
            photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
        }
    }
    
    // MARK: - 사진 설정 객체 생성.
    
    // 사용자가 UI에서 활성화한 기능으로 사진 설정 객체를 생성합니다.
    private func createPhotoSettings(with features: PhotoFeatures) -> AVCapturePhotoSettings {
        // 사진 캡처를 구성할 새로운 설정 객체 생성.
        var photoSettings = AVCapturePhotoSettings()
        
        // 장치가 지원하면 HEIF 형식으로 사진을 캡처합니다.
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        
        /// 캡처할 미리보기 이미지의 형식을 설정합니다. `photoSettings` 객체는 기본 이미지와의 호환성에 따라 사용 가능한 미리보기 형식 유형을 반환합니다.
        if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
            photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
        }
        
        /// 사진 출력이 지원하는 최대 차원으로 설정합니다.
        /// `CaptureService`는 캡처 파이프라인이 변경될 때마다 사진 출력의 `maxPhotoDimensions`를 자동으로 업데이트합니다.
        photoSettings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        
        // 사진 출력이 Live Photo 캡처를 지원하는 경우 영상 파일 URL을 설정합니다.
        photoSettings.livePhotoMovieFileURL = features.isLivePhotoEnabled ? URL.movieFileURL : nil
        
        // 이 캡처에서 속도와 품질 중 우선순위를 설정합니다.
        if let prioritization = AVCapturePhotoOutput.QualityPrioritization(rawValue: features.qualityPrioritization.rawValue) {
            photoSettings.photoQualityPrioritization = prioritization
        }
        
        return photoSettings
    }
    
    /// 사진 캡처 대리자의 진행 상황을 모니터링합니다.
    ///
    /// `PhotoCaptureDelegate`는 현재 진행 상태를 나타내는 값들의 비동기 스트림을 생성합니다.
    /// 앱은 활동 값을 뷰 계층으로 전달하여 UI가 적절히 업데이트되도록 합니다.
    private func monitorProgress(of delegate: PhotoCaptureDelegate, isolation: isolated (any Actor)? = #isolation) {
        Task {
            _ = isolation
            var isLivePhoto = false
            // 시스템이 캡처를 수행하는 동안 대리자의 활동을 비동기적으로 모니터링합니다.
            for await activity in delegate.activityStream {
                var currentActivity = activity
                /// 대리자의 활동 값이 여러 번 `isLivePhoto`가 `true`일 수 있습니다.
                /// 값이 이전 상태에서 변경될 때만 카운트를 증가/감소시킵니다.
                if activity.isLivePhoto != isLivePhoto {
                    isLivePhoto = activity.isLivePhoto
                    // 적절히 증가 또는 감소시킵니다.
                    livePhotoCount += isLivePhoto ? 1 : -1
                    if livePhotoCount > 1 {
                        /// 동시에 여러 개의 Live Photo가 진행 중일 때 `isLivePhoto`를 `true`로 설정합니다.
                        /// 이렇게 하면 UI에서 "Live" 배지가 깜박이지 않도록 방지할 수 있습니다.
                        currentActivity = .photoCapture(willCapture: activity.willCapture, isLivePhoto: true)
                    }
                }
                captureActivity = currentActivity
            }
        }
    }
    
    // MARK: - 사진 출력 구성 업데이트
    
    /// 사진 출력을 재구성하고 출력 서비스의 기능을 그에 맞게 업데이트합니다.
    ///
    /// `CaptureService`는 카메라를 변경할 때마다 이 메서드를 호출합니다.
    ///
    func updateConfiguration(for device: AVCaptureDevice) {
        // 지원하는 모든 기능을 활성화합니다.
        photoOutput.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.last ?? .zero
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        photoOutput.maxPhotoQualityPrioritization = .quality
        photoOutput.isResponsiveCaptureEnabled = photoOutput.isResponsiveCaptureSupported
        photoOutput.isFastCapturePrioritizationEnabled = photoOutput.isFastCapturePrioritizationSupported
        photoOutput.isAutoDeferredPhotoDeliveryEnabled = photoOutput.isAutoDeferredPhotoDeliverySupported
        updateCapabilities(for: device)
    }
    
    private func updateCapabilities(for device: AVCaptureDevice) {
        capabilities = CaptureCapabilities(isLivePhotoCaptureSupported: photoOutput.isLivePhotoCaptureSupported)
    }
}

typealias PhotoContinuation = CheckedContinuation<Photo, Error>

// MARK: - 캡처된 사진을 처리할 사진 캡처 대리자.

/// `AVCapturePhotoCaptureDelegate` 프로토콜을 채택하여 사진 캡처 생애 주기 이벤트에 응답하는 객체.
///
/// 이 대리자는 현재 처리 상태를 나타내는 이벤트 스트림을 생성합니다.
private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    
    private let continuation: PhotoContinuation
    
    private var isLivePhoto = false
    private var isProxyPhoto = false
    
    private var photoData: Data?
    private var livePhotoMovieURL: URL?
    
    /// 진행 상태를 나타내는 캡처 활동 값 스트림.
    let activityStream: AsyncStream<CaptureActivity>
    private let activityContinuation: AsyncStream<CaptureActivity>.Continuation
    
    /// 처리 완료 시 호출할 확인된 continuation을 사용하여 새로운 대리자 객체를 생성합니다.
    init(continuation: PhotoContinuation) {
        self.continuation = continuation
        
        let (activityStream, activityContinuation) = AsyncStream.makeStream(of: CaptureActivity.self)
        self.activityStream = activityStream
        self.activityContinuation = activityContinuation
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Live Photo 캡처인지 여부를 확인합니다.
        isLivePhoto = resolvedSettings.livePhotoMovieDimensions != .zero
        activityContinuation.yield(.photoCapture(isLivePhoto: isLivePhoto))
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // 캡처가 시작될 것임을 신호로 보냅니다.
        activityContinuation.yield(.photoCapture(willCapture: true, isLivePhoto: isLivePhoto))
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Live Photo 캡처가 끝났음을 나타냅니다.
        activityContinuation.yield(.photoCapture(isLivePhoto: false))
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error {
            logger.debug("Live Photo 동영상 처리 오류: \(String(describing: error))")
        }
        livePhotoMovieURL = outputFileURL
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy deferredPhotoProxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        if let error = error {
            logger.debug("지연된 사진 캡처 오류: \(error)")
            return
        }
        // 이 사진의 데이터를 캡처합니다.
        photoData = deferredPhotoProxy?.fileDataRepresentation()
        isProxyPhoto = true
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            logger.debug("사진 캡처 오류: \(String(describing: error))")
            return
        }
        photoData = photo.fileDataRepresentation()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        
        defer {
            /// 활동 스트림을 종료하기 위해 continuation을 완료합니다.
            activityContinuation.finish()
        }
        
        // 오류가 발생하면 continuation을 재개하여 오류를 던지고 반환합니다.
        if let error {
            continuation.resume(throwing: error)
            return
        }
        
        // 사진 데이터가 없으면 continuation을 재개하여 오류를 던지고 반환합니다.
        guard let photoData else {
            continuation.resume(throwing: PhotoCaptureError.noPhotoData)
            return
        }
        
        /// `MediaLibrary`에 저장할 사진 객체를 생성합니다.
        let photo = Photo(data: photoData, isProxy: isProxyPhoto, livePhotoMovieURL: livePhotoMovieURL)
        // 캡처된 사진을 반환하기 위해 continuation을 재개합니다.
        continuation.resume(returning: photo)
    }
}
