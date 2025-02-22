/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.

 개요:
 앱에 필요한 지원 데이터 타입들.
*/

import AVFoundation

// MARK: - 지원 타입

/// 카메라의 현재 상태를 설명하는 열거형.
enum CameraStatus {
    /// 생성 시 초기 상태.
    case unknown
    /// 카메라나 마이크에 접근을 허용하지 않는 상태.
    case unauthorized
    /// 카메라가 시작되지 못한 상태.
    case failed
    /// 카메라가 정상적으로 실행 중인 상태.
    case running
    /// 더 높은 우선순위의 미디어 처리로 인해 카메라가 중단된 상태.
    case interrupted
}

/// 캡처 서비스가 지원하는 활동 상태를 정의하는 열거형.
///
/// 이 타입은 `CaptureService` 액터의 활성 상태에 대한 피드백을 UI에 제공합니다.
enum CaptureActivity {
    case idle
    /// 캡처 서비스가 사진 촬영을 수행 중인 상태.
    case photoCapture(willCapture: Bool = false, isLivePhoto: Bool = false)
    /// 캡처 서비스가 동영상 촬영을 수행 중인 상태.
    case movieCapture(duration: TimeInterval = 0.0)
    
    var isLivePhoto: Bool {
        if case .photoCapture(_, let isLivePhoto) = self {
            return isLivePhoto
        }
        return false
    }
    
    var willCapture: Bool {
        if case .photoCapture(let willCapture, _) = self {
            return willCapture
        }
        return false
    }
    
    var currentTime: TimeInterval {
        if case .movieCapture(let duration) = self {
            return duration
        }
        return .zero
    }
    
    var isRecording: Bool {
        if case .movieCapture(_) = self {
            return true
        }
        return false
    }
}

/// 카메라가 지원하는 캡처 모드를 나열하는 열거형.
enum CaptureMode: String, Identifiable, CaseIterable, Codable {
    var id: Self { self }
    /// 사진 촬영을 활성화하는 모드.
    case photo
    /// 동영상 촬영을 활성화하는 모드.
    case video
    
    var systemName: String {
        switch self {
        case .photo:
            "camera.fill"
        case .video:
            "video.fill"
        }
    }
}

/// 캡처된 사진을 나타내는 구조체.
struct Photo: Sendable {
    let data: Data
    let isProxy: Bool
    let livePhotoMovieURL: URL?
}

/// 영상 URL과 함께 균일한 타입 식별자(UTI)를 포함하는 구조체.
struct Movie: Sendable {
    /// 디스크에서 파일의 임시 위치.
    let url: URL
}

struct PhotoFeatures {
    let isLivePhotoEnabled: Bool
    let qualityPrioritization: QualityPrioritization
}

/// `CaptureService`의 현재 구성에서 캡처 기능을 나타내는 구조체.
struct CaptureCapabilities {

    let isLivePhotoCaptureSupported: Bool
    let isHDRSupported: Bool
    
    init(isLivePhotoCaptureSupported: Bool = false,
         isHDRSupported: Bool = false) {
        self.isLivePhotoCaptureSupported = isLivePhotoCaptureSupported
        self.isHDRSupported = isHDRSupported
    }
    
    /// 기능이 알려지지 않은 기본값을 가진 `CaptureCapabilities` 객체.
    static let unknown = CaptureCapabilities()
}

enum QualityPrioritization: Int, Identifiable, CaseIterable, CustomStringConvertible, Codable {
    var id: Self { self }
    /// 속도 우선 모드.
    case speed = 1
    /// 균형 모드.
    case balanced
    /// 품질 우선 모드.
    case quality
    
    var description: String {
        switch self {
        case .speed:
            return "속도 우선"
        case .balanced:
            return "균형"
        case .quality:
            return "품질 우선"
        }
    }
}

enum CameraError: Error {
    /// 비디오 장치가 사용 불가능한 상태.
    case videoDeviceUnavailable
    /// 오디오 장치가 사용 불가능한 상태.
    case audioDeviceUnavailable
    /// 입력 추가에 실패한 상태.
    case addInputFailed
    /// 출력 추가에 실패한 상태.
    case addOutputFailed
    /// 설정에 실패한 상태.
    case setupFailed
    /// 장치 변경에 실패한 상태.
    case deviceChangeFailed
}

protocol OutputService {
    associatedtype Output: AVCaptureOutput
    var output: Output { get }
    var captureActivity: CaptureActivity { get }
    var capabilities: CaptureCapabilities { get }
    /// 지정된 장치에 대해 구성을 업데이트합니다.
    func updateConfiguration(for device: AVCaptureDevice)
    /// 비디오 회전 각도를 설정합니다.
    func setVideoRotationAngle(_ angle: CGFloat)
}

extension OutputService {
    func setVideoRotationAngle(_ angle: CGFloat) {
        // 출력 객체의 비디오 연결에서 회전 각도를 설정합니다.
        output.connection(with: .video)?.videoRotationAngle = angle
    }
    func updateConfiguration(for device: AVCaptureDevice) {}
}
