/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 캡처 세션과 입력 및 출력을 관리하는 객체.
 */

import Foundation
import AVFoundation
import Combine

/// 캡처 세션, 장치 입력 및 캡처 출력을 포함한 캡처 파이프라인을 관리하는 액터(actor).
/// 앱은 이 타입을 `actor`로 정의하여 모든 카메라 작업이 `@MainActor` 외부에서 실행되도록 보장합니다.
actor CaptureService {
    
    /// 캡처 서비스가 대기중인지, 캡처 중인지 나타내는 값.
    @Published private(set) var captureActivity: CaptureActivity = .idle
    /// 현재 캡처 서비스의 캡처 가능 상태를 나타내는 값.
    @Published private(set) var captureCapabilities = CaptureCapabilities.unknown
    /// 전화 수신과 같은 높은 우선순위 이벤트로 인해 앱이 중단되었는지 여부를 나타내는 Boolean 값.
    @Published private(set) var isInterrupted = false
    /// 사용자가 HDR 비디오 캡처를 활성화했는지 여부를 나타내는 Boolean 값.
    @Published var isHDRVideoEnabled = false
    /// 캡처 컨트롤이 전체 화면 모드로 표시되는지 여부를 나타내는 Boolean 값.
    @Published var isShowingFullscreenControls = false
    
    /// 미리보기 대상과 캡처 세션을 연결하는 타입.
    nonisolated let previewSource: PreviewSource
    
    // 앱의 캡처 세션.
    private let captureSession = AVCaptureSession()
    
    // 사진 캡처 동작을 관리하는 객체.
    private let photoCapture = PhotoCapture()
    
    // 비디오 캡처 동작을 관리하는 객체.
    private let movieCapture = MovieCapture()
    
    // 내부적으로 사용되는 출력 서비스 컬렉션.
    private var outputServices: [any OutputService] { [photoCapture, movieCapture] }
    
    // 현재 선택된 카메라의 비디오 입력.
    private var activeVideoInput: AVCaptureDeviceInput?
    
    // 사진 또는 비디오 캡처 모드. 기본값은 사진 모드.
    private(set) var captureMode = CaptureMode.photo
    
    // 캡처 장치를 검색하는 객체.
    private let deviceLookup = DeviceLookup()
    
    // 시스템이 선호하는 카메라 상태를 모니터링하는 객체.
    private let systemPreferredCamera = SystemPreferredCameraObserver()
    
    // 비디오 장치의 회전 상태를 모니터링하는 객체.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator!
    private var rotationObservers = [AnyObject]()
    
    // 액터가 필요한 구성을 완료했는지 여부를 나타내는 Boolean 값.
    private var isSetUp = false
    
    // 캡처 컨트롤 활성화 및 표시 이벤트에 응답하는 delegate 객체.
    private var controlsDelegate = CaptureControlsDelegate()
    
    // 기기 식별자를 기준으로 캡처 컨트롤을 저장하는 맵.
    private var controlsMap: [String: [AVCaptureControl]] = [:]
    
    // 캡처 컨트롤 작업을 처리하는 직렬 디스패치 큐.
    private let sessionQueue = DispatchSerialQueue(label: "com.example.apple-samplecode.AVCam.sessionQueue")
    
    // 세션 큐를 액터의 실행기로 설정.
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        sessionQueue.asUnownedSerialExecutor()
    }
    
    init() {
        // 미리보기 뷰와 캡처 세션을 연결하는 소스 객체 생성.
        previewSource = DefaultPreviewSource(session: captureSession)
    }
    
    // MARK: - 권한 관리
    /// 사용자가 이 앱이 기기의 카메라 및 마이크를 사용할 수 있도록 승인했는지 나타내는 Boolean 값.
    /// 사용자가 이전에 승인하지 않았다면, 이 속성을 조회할 때 권한 요청 창이 표시됩니다.
    var isAuthorized: Bool {
        get async {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            // 사용자가 이전에 카메라 접근을 승인했는지 확인.
            var isAuthorized = status == .authorized
            // 시스템이 아직 승인 상태를 결정하지 않았다면 권한 요청 창을 표시.
            if status == .notDetermined {
                isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
            }
            return isAuthorized
        }
    }
    
    // MARK: - 캡처 세션 life cycle
    func start(with state: CameraState) async throws {
        // 초기 운영 상태 설정.
        captureMode = state.captureMode
        isHDRVideoEnabled = state.isVideoHDREnabled
        
        // 권한이 없거나 세션이 이미 실행 중이라면 return.
        guard await isAuthorized, !captureSession.isRunning else { return }
        // 세션을 설정하고 실행 시작.
        try setUpSession()
        captureSession.startRunning()
    }
    
    // MARK: - 캡처 설정
    // 초기 캡처 세션 구성을 수행.
    private func setUpSession() throws {
        // 이미 설정된 경우 return.
        guard !isSetUp else { return }
        
        // 내부 상태 및 알림 관찰.
        observeOutputServices()
        observeNotifications()
        observeCaptureControlsState()
        
        do {
            // 기본 카메라 및 마이크 검색.
            let defaultCamera = try deviceLookup.defaultCamera
            let defaultMic = try deviceLookup.defaultMic
            
            // 기본 카메라 및 마이크 입력 추가.
            activeVideoInput = try addInput(for: defaultCamera)
            try addInput(for: defaultMic)
            
            // 현재 캡처 모드에 따라 세션 프리셋 구성.
            captureSession.sessionPreset = captureMode == .photo ? .photo : .hd4K3840x2160
            // 기본 출력 타입으로 사진 캡처 출력 추가.
            try addOutput(photoCapture.output)
            // 캡처 모드가 비디오인 경우, 동영상 캡처 출력 추가.
            if captureMode == .video {
                // 기본 출력 타입으로 동영상 출력 추가.
                try addOutput(movieCapture.output)
                setHDRVideoEnabled(isHDRVideoEnabled)
            }
            
            // 카메라 컨트롤에서 사용할 컨트롤 구성.
            configureControls(for: defaultCamera)
            // 시스템이 선호하는 카메라 상태 모니터링.
            monitorSystemPreferredCamera()
            // 기본 비디오 기기를 위한 회전 코디네이터 구성.
            createRotationCoordinator(for: defaultCamera)
            // 기본 카메라의 피사체 영역 변경 사항을 감지.
            observeSubjectAreaChanges(of: defaultCamera)
            // 서비스의 지원 가능 기능 업데이트.
            updateCaptureCapabilities()
            
            isSetUp = true
        } catch {
            throw CameraError.setupFailed
        }
    }
    
    // 캡처 장치를 캡처 세션에 입력으로 추가합니다.
    @discardableResult
    private func addInput(for device: AVCaptureDevice) throws -> AVCaptureDeviceInput {
        let input = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        } else {
            throw CameraError.addInputFailed
        }
        return input
    }
    
    // 지정된 캡처 장치를 캡처 세션에 출력으로 추가합니다.
    private func addOutput(_ output: AVCaptureOutput) throws {
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        } else {
            throw CameraError.addOutputFailed
        }
    }
    
    // 현재 활성 비디오 입력에 해당하는 장치.
    private var currentDevice: AVCaptureDevice {
        guard let device = activeVideoInput?.device else {
            fatalError("현재 비디오 입력에 대한 장치를 찾을 수 없습니다.")
        }
        return device
    }
    
    // MARK: - 캡처 컨트롤
    
    private func configureControls(for device: AVCaptureDevice) {
        
        // 호스트 장치가 캡처 컨트롤을 지원하지 않으면 조기 종료.
        guard captureSession.supportsControls else { return }
        
        // 캡처 세션 구성 시작.
        captureSession.beginConfiguration()
        
        // 기존에 설정된 컨트롤이 있다면 제거.
        for control in captureSession.controls {
            captureSession.removeControl(control)
        }
        
        // 새로운 컨트롤을 생성하고 캡처 세션에 추가.
        for control in createControls(for: device) {
            if captureSession.canAddControl(control) {
                captureSession.addControl(control)
            } else {
                logger.info("컨트롤 \(control)를 추가할 수 없습니다.")
            }
        }
        
        // 컨트롤 delegate 설정.
        captureSession.setControlsDelegate(controlsDelegate, queue: sessionQueue)
        
        // 캡처 세션 구성 적용.
        captureSession.commitConfiguration()
    }
    
    func createControls(for device: AVCaptureDevice) -> [AVCaptureControl] {
        // 해당 장치에 대한 기존 캡처 컨트롤이 있으면 가져오기.
        guard let controls = controlsMap[device.uniqueID] else {
            // 기본 컨트롤 정의.
            var controls = [
                AVCaptureSystemZoomSlider(device: device),
                AVCaptureSystemExposureBiasSlider(device: device)
            ]
            // 장치가 사용자 지정 렌즈 위치 설정을 지원하는 경우 렌즈 위치 컨트롤 생성.
            if device.isLockingFocusWithCustomLensPositionSupported {
                // 0에서 1까지 값을 조정할 수 있는 슬라이더 생성.
                let lensSlider = AVCaptureSlider("Lens Position", symbolName: "circle.dotted.circle", in: 0...1)
                // 세션 큐에서 슬라이더의 동작 수행.
                lensSlider.setActionQueue(sessionQueue) { lensPosition in
                    do {
                        try device.lockForConfiguration()
                        device.setFocusModeLocked(lensPosition: lensPosition)
                        device.unlockForConfiguration()
                    } catch {
                        logger.info("렌즈 위치를 변경할 수 없습니다: \(error)")
                    }
                }
                // 컨트롤 배열에 슬라이더 추가.
                controls.append(lensSlider)
            }
            // 이후 사용을 위해 컨트롤 저장.
            controlsMap[device.uniqueID] = controls
            return controls
        }
        
        // 기존에 생성된 컨트롤 반환.
        return controls
    }
    
    // MARK: - 캡처 모드 선택
    
    /// 캡처 모드를 변경합니다. 모드는 `photo` 또는 `video`가 될 수 있습니다.
    ///
    /// - Parameter `captureMode`: 활성화할 캡처 모드.
    func setCaptureMode(_ captureMode: CaptureMode) throws {
        // 세션 구성을 수행하기 전에 내부 캡처 모드 값을 업데이트합니다.
        self.captureMode = captureMode
        
        // 설정 변경을 atomically 하게 수행합니다.
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        
        // 선택한 캡처 모드에 따라 캡처 세션을 구성합니다.
        switch captureMode {
        case .photo:
            // Live Photo 촬영을 위해 동영상 캡처 출력을 제거해야 합니다.
            captureSession.sessionPreset = .photo
            captureSession.removeOutput(movieCapture.output)
        case .video:
            captureSession.sessionPreset = .hd4K3840x2160
            try addOutput(movieCapture.output)
            if isHDRVideoEnabled {
                setHDRVideoEnabled(true)
            }
        }
        
        // 구성 변경 후 제공되는 기능을 업데이트합니다.
        updateCaptureCapabilities()
    }
    
    // MARK: - 장치 선택
    
    /// 비디오 입력을 제공하는 캡처 장치를 변경합니다.
    ///
    /// 앱은 사용자가 UI에서 카메라 변경 버튼을 눌렀을 때 이 메서드를 호출합니다.
    /// 이 구현은 전면 카메라와 후면 카메라 간 전환을 처리하며,
    /// iPadOS에서는 연결된 외부 카메라도 지원합니다.
    func selectNextVideoDevice() {
        // 사용 가능한 비디오 캡처 장치 목록.
        let videoDevices = deviceLookup.cameras
        
        // 현재 선택된 비디오 장치의 인덱스를 찾습니다.
        let selectedIndex = videoDevices.firstIndex(of: currentDevice) ?? 0
        // 다음 인덱스를 가져옵니다.
        var nextIndex = selectedIndex + 1
        // 인덱스가 유효하지 않으면 처음으로 되돌립니다.
        if nextIndex == videoDevices.endIndex {
            nextIndex = 0
        }
        
        let nextDevice = videoDevices[nextIndex]
        // 세션의 활성 캡처 장치를 변경합니다.
        changeCaptureDevice(to: nextDevice)
        
        // 이 메서드는 사용자가 카메라 전환을 요청했을 때만 호출됩니다.
        // 새 선택을 사용자의 기본 카메라로 설정합니다.
        AVCaptureDevice.userPreferredCamera = nextDevice
    }
    
    // 비디오 캡처에 사용하는 장치를 변경합니다.
    private func changeCaptureDevice(to device: AVCaptureDevice) {
        // 이 메서드를 호출하기 전에 유효한 비디오 입력이 있어야 합니다.
        guard let currentInput = activeVideoInput else { fatalError() }
        
        // 다음 설정을 begin/commit 구성 블록 내에서 수행합니다.
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        
        // 새로운 입력을 연결하기 전에 기존 비디오 입력을 제거합니다.
        captureSession.removeInput(currentInput)
        do {
            // 새로운 입력 및 장치를 캡처 세션에 연결하려 시도합니다.
            activeVideoInput = try addInput(for: device)
            // 새로운 장치에 대한 캡처 컨트롤을 구성합니다.
            configureControls(for: device)
            // 새로운 장치에 대한 회전 코디네이터를 설정합니다.
            createRotationCoordinator(for: device)
            // 장치 관찰을 등록합니다.
            observeSubjectAreaChanges(of: device)
            // 제공되는 기능을 업데이트합니다.
            updateCaptureCapabilities()
        } catch {
            // 실패할 경우 기존 카메라를 다시 연결합니다.
            captureSession.addInput(currentInput)
        }
    }
    
    /// 시스템 기본 카메라 선택 변경을 모니터링합니다.
    ///
    /// iPadOS는 외부 카메라를 지원합니다.
    /// 사용자가 iPad에 외부 카메라를 연결하면 해당 장치를 사용하려는 의도로 간주됩니다.
    /// 시스템은 이에 대응하여 시스템 기본 카메라(SPC) 선택을 새로운 장치로 업데이트합니다.
    /// 이때, 현재 선택된 카메라가 SPC가 아니라면 새 장치로 전환합니다.
    private func monitorSystemPreferredCamera() {
        Task {
            // 시스템 기본 카메라(SPC) 값 변경을 모니터링하는 객체입니다.
            for await camera in systemPreferredCamera.changes {
                // SPC가 현재 선택된 카메라가 아니라면 해당 장치로 변경을 시도합니다.
                if let camera, currentDevice != camera {
                    logger.debug("카메라 선택을 시스템에서 선호하는 카메라로 변경합니다.")
                    changeCaptureDevice(to: camera)
                }
            }
        }
    }
    
    // MARK: - 회전 처리
    
    /// 지정된 디바이스에 대한 새로운 회전 코디네이터를 생성하고 상태를 관찰하여 회전 변화를 감지합니다.
    private func createRotationCoordinator(for device: AVCaptureDevice) {
        // 해당 디바이스에 대한 새로운 회전 코디네이터를 생성합니다.
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
        
        // 미리보기 및 출력 연결의 초기 회전 상태를 설정합니다.
        updatePreviewRotation(rotationCoordinator.videoRotationAngleForHorizonLevelPreview)
        updateCaptureRotation(rotationCoordinator.videoRotationAngleForHorizonLevelCapture)
        
        // 이전 관찰을 취소합니다.
        rotationObservers.removeAll()
        
        // 회전 변화를 감지할 수 있도록 옵저버를 추가합니다.
        rotationObservers.append(
            rotationCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] _, change in
                guard let self, let angle = change.newValue else { return }
                // 미리보기 회전을 업데이트합니다.
                Task { await self.updatePreviewRotation(angle) }
            }
        )
        
        rotationObservers.append(
            rotationCoordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { [weak self] _, change in
                guard let self, let angle = change.newValue else { return }
                // 촬영 시 회전 값을 업데이트합니다.
                Task { await self.updateCaptureRotation(angle) }
            }
        )
    }
    
    /// 미리보기 레이어의 회전 각도를 업데이트합니다.
    private func updatePreviewRotation(_ angle: CGFloat) {
        let previewLayer = videoPreviewLayer
        Task { @MainActor in
            // 비디오 미리보기의 초기 회전 각도를 설정합니다.
            previewLayer.connection?.videoRotationAngle = angle
        }
    }
    
    /// 출력 서비스의 회전 각도를 업데이트합니다.
    private func updateCaptureRotation(_ angle: CGFloat) {
        // 모든 출력 서비스의 방향을 업데이트합니다.
        outputServices.forEach { $0.setVideoRotationAngle(angle) }
    }
    
    /// 캡처 세션의 연결된 미리보기 레이어를 반환합니다.
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        // 캡처 세션이 연결된 미리보기 레이어를 가져옵니다.
        guard let previewLayer = captureSession.connections.compactMap({ $0.videoPreviewLayer }).first else {
            fatalError("앱이 잘못 구성되었습니다. 캡처 세션에는 미리보기 레이어와 연결된 객체가 있어야 합니다.")
        }
        return previewLayer
    }
    
    // MARK: - 자동 초점 및 노출
    
    /// 한 번만 실행되는 자동 초점 및 노출 조정 작업을 수행합니다.
    ///
    /// 사용자가 미리보기 영역을 탭하면 이 메서드가 호출됩니다.
    func focusAndExpose(at point: CGPoint) {
        // 전달된 좌표는 뷰 공간 기준이므로, 이를 디바이스 좌표로 변환합니다.
        let devicePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
        do {
            // 사용자 조작에 의해 초점 및 노출을 수행합니다.
            try focusAndExpose(at: devicePoint, isUserInitiated: true)
        } catch {
            logger.debug("초점 및 노출 조정 작업을 수행할 수 없습니다. \(error)")
        }
    }
    
    /// 지정된 디바이스에 대해 `subjectAreaDidChangeNotification` 알림을 감지합니다.
    private func observeSubjectAreaChanges(of device: AVCaptureDevice) {
        // 이전의 관찰 작업을 취소합니다.
        subjectAreaChangeTask?.cancel()
        subjectAreaChangeTask = Task {
            // 이 알림이 발생하면 true를 반환합니다.
            for await _ in NotificationCenter.default.notifications(named: AVCaptureDevice.subjectAreaDidChangeNotification, object: device).compactMap({ _ in true }) {
                // 시스템이 자동으로 초점 및 노출을 조정하도록 수행합니다.
                try? focusAndExpose(at: CGPoint(x: 0.5, y: 0.5), isUserInitiated: false)
            }
        }
    }
    private var subjectAreaChangeTask: Task<Void, Never>?
    
    /// 디바이스의 초점 및 노출을 조정합니다.
    private func focusAndExpose(at devicePoint: CGPoint, isUserInitiated: Bool) throws {
        // 현재 사용 중인 디바이스를 가져옵니다.
        let device = currentDevice
        
        // 아래의 모드 및 관심 지점 설정을 위해 디바이스의 독점 잠금이 필요합니다.
        try device.lockForConfiguration()
        
        let focusMode = isUserInitiated ? AVCaptureDevice.FocusMode.autoFocus : .continuousAutoFocus
        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
            device.focusPointOfInterest = devicePoint
            device.focusMode = focusMode
        }
        
        let exposureMode = isUserInitiated ? AVCaptureDevice.ExposureMode.autoExpose : .continuousAutoExposure
        if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = exposureMode
        }
        
        // 사용자가 초점 및 노출 조정을 실행한 경우, 피사체 영역 변경 감지를 활성화합니다.
        // 이를 통해 디바이스의 피사체 영역이 변경되면 이 메서드가 다시 호출되어 연속 자동 초점 및 노출로 재설정됩니다.
        device.isSubjectAreaChangeMonitoringEnabled = isUserInitiated
        
        // 잠금을 해제합니다.
        device.unlockForConfiguration()
    }
    
    // MARK: - 사진 촬영
    
    /// 사진을 캡처합니다.
    func capturePhoto(with features: PhotoFeatures) async throws -> Photo {
        try await photoCapture.capturePhoto(with: features)
    }
    
    // MARK: - 동영상 촬영
    
    /// 비디오 녹화를 시작합니다. 사용자가 녹화를 중지할 때까지 녹화가 계속됩니다.
    /// 녹화를 중지하려면 `stopRecording()` 메서드를 호출합니다.
    func startRecording() {
        movieCapture.startRecording()
    }
    
    /// 녹화를 중지하고 캡처된 영상을 반환합니다.
    func stopRecording() async throws -> Movie {
        try await movieCapture.stopRecording()
    }
    
    /// HDR 비디오 촬영 여부를 설정합니다.
    func setHDRVideoEnabled(_ isEnabled: Bool) {
        // 아래 설정을 begin/commit 구성 블록 내에서 처리합니다.
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        do {
            // 현재 디바이스가 10비트 HDR 포맷을 지원하는 경우 이를 활성화합니다.
            if isEnabled, let format = currentDevice.activeFormat10BitVariant {
                try currentDevice.lockForConfiguration()
                currentDevice.activeFormat = format
                currentDevice.unlockForConfiguration()
                isHDRVideoEnabled = true
            } else {
                captureSession.sessionPreset = .hd4K3840x2160
                isHDRVideoEnabled = false
            }
        } catch {
            logger.error("장치를 lock 할 수 없어 HDR 비디오 촬영을 활성화할 수 없습니다.")
        }
    }
    
    // MARK: - 내부 상태 관리
    
    /// 액터의 상태를 업데이트하여 명시된 기능이 정확하도록 보장합니다.
    ///
    /// 캡처 세션이 변경될 때(예: 모드 변경 또는 입력 장치 변경) 서비스는 이 메서드를 호출하여 설정 및 기능을 업데이트합니다.
    /// 앱은 이 상태를 사용하여 사용자 인터페이스에서 어떤 기능을 활성화할지 결정합니다.
    private func updateCaptureCapabilities() {
        // 출력 서비스 설정을 업데이트합니다.
        outputServices.forEach { $0.updateConfiguration(for: currentDevice) }
        
        // 선택된 모드에 따라 캡처 서비스의 기능을 설정합니다.
        switch captureMode {
        case .photo:
            captureCapabilities = photoCapture.capabilities
        case .video:
            captureCapabilities = movieCapture.capabilities
        }
    }
    
    /// 사진 및 동영상 캡처 서비스의 `captureActivity` 값을 병합하여 액터의 속성에 할당합니다.
    private func observeOutputServices() {
        Publishers.Merge(photoCapture.$captureActivity, movieCapture.$captureActivity)
            .assign(to: &$captureActivity)
    }
    
    /// 캡처 컨트롤이 전체 화면 모드로 들어가거나 나올 때의 상태 변화를 감지합니다.
    private func observeCaptureControlsState() {
        controlsDelegate.$isShowingFullscreenControls
            .assign(to: &$isShowingFullscreenControls)
    }
    
    /// 캡처와 관련된 알림을 감지합니다.
    private func observeNotifications() {
        Task {
            for await reason in NotificationCenter.default.notifications(named: AVCaptureSession.wasInterruptedNotification)
                .compactMap({ $0.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject? })
                .compactMap({ AVCaptureSession.InterruptionReason(rawValue: $0.integerValue) }) {
                /// `isInterrupted` 상태를 적절하게 설정합니다.
                isInterrupted = [.audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient].contains(reason)
            }
        }
        
        Task {
            // 중단이 종료되었을 때의 알림을 감지합니다.
            for await _ in NotificationCenter.default.notifications(named: AVCaptureSession.interruptionEndedNotification) {
                isInterrupted = false
            }
        }
        
        Task {
            for await error in NotificationCenter.default.notifications(named: AVCaptureSession.runtimeErrorNotification)
                .compactMap({ $0.userInfo?[AVCaptureSessionErrorKey] as? AVError }) {
                // 시스템이 미디어 서비스를 재설정하면 캡처 세션이 중지될 수 있습니다.
                if error.code == .mediaServicesWereReset {
                    if !captureSession.isRunning {
                        captureSession.startRunning()
                    }
                }
            }
        }
    }
}

class CaptureControlsDelegate: NSObject, AVCaptureSessionControlsDelegate {
    
    @Published private(set) var isShowingFullscreenControls = false
    
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        logger.debug("캡처 컨트롤이 활성화되었습니다.")
    }
    
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        isShowingFullscreenControls = true
        logger.debug("캡처 컨트롤이 전체 화면 모드로 전환됩니다.")
    }
    
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        isShowingFullscreenControls = false
        logger.debug("캡처 컨트롤이 전체 화면 모드를 종료합니다.")
    }
    
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        logger.debug("캡처 컨트롤이 비활성화되었습니다.")
    }
}
