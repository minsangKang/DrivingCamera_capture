/*
 이 샘플의 라이선스 정보는 LICENSE.txt 파일을 참조하세요.
 
 개요:
 사용자 사진 라이브러리에 사진과 영상을 저장하는 객체.
 */

import Foundation
import Photos
import UIKit

/// 사용자 사진 라이브러리에 사진과 영상을 저장하는 객체.
actor MediaLibrary {
    
    // 미디어 라이브러리가 발생시킬 수 있는 오류들.
    enum Error: Swift.Error {
        case unauthorized
        case saveFailed
    }
    
    /// 앱이 미디어를 캡처한 후 생성하는 썸네일 이미지를 비동기 스트림으로 제공.
    let thumbnails: AsyncStream<CGImage?>
    private let continuation: AsyncStream<CGImage?>.Continuation?
    
    /// 새로운 미디어 라이브러리 객체를 생성.
    init() {
        let (thumbnails, continuation) = AsyncStream.makeStream(of: CGImage?.self)
        self.thumbnails = thumbnails
        self.continuation = continuation
    }
    
    // MARK: - 권한 관리
    
    private var isAuthorized: Bool {
        get async {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            /// 사용자가 `PHPhotoLibrary` 접근을 허용했는지 여부 확인.
            var isAuthorized = status == .authorized
            // 시스템이 사용자의 권한 상태를 아직 결정하지 않은 경우 명시적으로 승인을 요청.
            if status == .notDetermined {
                // 사진 라이브러리에 미디어를 추가할 수 있도록 권한 요청.
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                isAuthorized = status == .authorized
            }
            return isAuthorized
        }
    }
    
    // MARK: - 미디어 저장
    
    /// 사진을 사진 라이브러리에 저장.
    func save(photo: Photo) async throws {
        let location = try await currentLocation
        try await performChange {
            let creationRequest = PHAssetCreationRequest.forAsset()
            
            // 기본 사진 저장.
            let options = PHAssetResourceCreationOptions()
            // 사진에 적합한 리소스 유형 지정.
            creationRequest.addResource(with: photo.isProxy ? .photoProxy : .photo, data: photo.data, options: options)
            creationRequest.location = location
            
            // Live Photo 데이터 저장.
            if let url = photo.livePhotoMovieURL {
                let livePhotoOptions = PHAssetResourceCreationOptions()
                livePhotoOptions.shouldMoveFile = true
                creationRequest.addResource(with: .pairedVideo, fileURL: url, options: livePhotoOptions)
            }
            
            return creationRequest.placeholderForCreatedAsset
        }
    }
    
    /// 영상를 사진 라이브러리에 저장.
    func save(movie: Movie) async throws {
        let location = try await currentLocation
        try await performChange {
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .video, fileURL: movie.url, options: options)
            creationRequest.location = location
            return creationRequest.placeholderForCreatedAsset
        }
    }
    
    // 사용자 사진 라이브러리에 변경을 기록하는 템플릿 메소드.
    private func performChange(_ change: @Sendable @escaping () -> PHObjectPlaceholder?) async throws {
        guard await isAuthorized else {
            throw Error.unauthorized
        }
        
        do {
            var placeholder: PHObjectPlaceholder?
            try await PHPhotoLibrary.shared().performChanges {
                // 변경 클로저 실행.
                placeholder = change()
            }
            
            if let placeholder {
                /// 새로 생성된 `PHAsset` 인스턴스를 가져옵니다.
                guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [placeholder.localIdentifier],
                                                      options: nil).firstObject else { return }
                await createThumbnail(for: asset)
            }
        } catch {
            throw Error.saveFailed
        }
    }
    
    // MARK: - 썸네일 처리
    
    private func loadInitialThumbnail() async {
        // 사용자가 이미 앱에 Photos 라이브러리 쓰기 권한을 허용한 경우에만 초기 썸네일을 로드합니다.
        // 이 호출을 지연시켜 앱 시작 시 Photos 권한 요청이 뜨지 않도록 합니다.
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        if let asset = PHAsset.fetchAssets(with: options).lastObject {
            await createThumbnail(for: asset)
        }
    }
    
    private func createThumbnail(for asset: PHAsset) async {
        // 256x256 크기의 썸네일 이미지를 생성 요청.
        PHImageManager.default().requestImage(for: asset,
                                              targetSize: .init(width: 256, height: 256),
                                              contentMode: .default,
                                              options: nil) { [weak self] image, _ in
            // 최신 썸네일 이미지 설정.
            guard let self, let image = image else { return }
            continuation?.yield(image.cgImage)
        }
    }
    
    // MARK: - 위치 관리
    
    private let locationManager = CLLocationManager()
    
    private var currentLocation: CLLocation? {
        get async throws {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            // 첫 번째 위치 업데이트를 반환.
            return try await CLLocationUpdate.liveUpdates().first(where: { _ in true })?.location
        }
    }
}
