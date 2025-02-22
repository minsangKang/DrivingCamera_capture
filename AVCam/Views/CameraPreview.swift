/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 캡처된 콘텐츠의 비디오 미리보기를 제공하는 뷰.
 */

import SwiftUI
@preconcurrency import AVFoundation

struct CameraPreview: UIViewRepresentable {
    
    private let source: PreviewSource
    
    init(source: PreviewSource) {
        self.source = source
    }
    
    func makeUIView(context: Context) -> PreviewView {
        let preview = PreviewView()
        // 미리보기 레이어를 캡처 세션에 연결.
        source.connect(to: preview)
        return preview
    }
    
    func updateUIView(_ previewView: PreviewView, context: Context) {
        // No-op (작업 없음).
    }
    
    /// 캡처된 콘텐츠를 표시하는 클래스.
    ///
    /// 이 클래스는 캡처된 콘텐츠를 표시하는 `AVCaptureVideoPreviewLayer`를 소유합니다.
    ///
    class PreviewView: UIView, PreviewTarget {
        
        init() {
            super.init(frame: .zero)
#if targetEnvironment(simulator)
            // 캡처 API는 실제 장치에서 실행해야 합니다. 시뮬레이터에서 실행 중인 경우,
            // 비디오 피드를 나타내기 위해 정적 이미지를 표시합니다.
            let imageView = UIImageView(frame: UIScreen.main.bounds)
            imageView.image = UIImage(named: "video_mode")
            imageView.contentMode = .scaleAspectFill
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(imageView)
#endif
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        // 미리보기 레이어를 뷰의 백업 레이어로 사용.
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
        
        nonisolated func setSession(_ session: AVCaptureSession) {
            // 캡처 세션을 미리보기 레이어에 연결하여,
            // 레이어가 캡처된 콘텐츠의 실시간 뷰를 제공할 수 있도록 합니다.
            Task { @MainActor in
                previewLayer.session = session
            }
        }
    }
}

/// 미리보기 소스가 미리보기 대상을 연결할 수 있도록 하는 프로토콜.
///
/// 앱은 이 유형의 인스턴스를 클라이언트 계층에 제공하여
/// 캡처 세션을 `PreviewView` 뷰에 연결할 수 있게 합니다.
/// 캡처 객체를 UI 레이어에 명시적으로 노출하는 것을 방지하기 위해 이 프로토콜을 사용합니다.
protocol PreviewSource: Sendable {
    // 미리보기 대상을 이 소스에 연결.
    func connect(to target: PreviewTarget)
}

/// 앱의 캡처 세션을 `CameraPreview` 뷰에 전달하는 프로토콜.
protocol PreviewTarget {
    // 대상을 위한 캡처 세션을 설정.
    func setSession(_ session: AVCaptureSession)
}

/// 앱의 기본 `PreviewSource` 구현.
struct DefaultPreviewSource: PreviewSource {
    
    private let session: AVCaptureSession
    
    init(session: AVCaptureSession) {
        self.session = session
    }
    
    func connect(to target: PreviewTarget) {
        target.setSession(session)
    }
}
