import SwiftUI
import Combine
import UIKit
import Foundation
import AVFoundation
import Vision
import Photos

enum TimerPurpose {
    case gestureHold
    case captureDelay
}

enum HandGesture: String, CaseIterable, Equatable {
    case peace, open, fist
}

@MainActor
class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    @Published var deviceOrientation: UIDeviceOrientation = .portrait
    var videoOrientation: AVCaptureVideoOrientation = .portrait
    
    override init() {
        super.init()
           print("[DEBUG] CameraManager instance created: \(Unmanaged.passUnretained(self).toOpaque())")
       }
    
    @Published var currentGesture: HandGesture? = nil
    @Published var currentGestureName: String? = nil
    @Published var isCountdownActive: Bool = false  // カウントダウン中フラグ
    

    private let photoOutput = AVCapturePhotoOutput()

    private var captureDelayTimer: Timer? = nil

    func startCaptureCountdown() {
        self.isCountdownActive = true
        print("=== [Manager] isCountdownActive just set to true: \(isCountdownActive)")
        timerCount = 3
        // デバッグ用: カウントダウン状態とタイマー値を出力
        print("⏲️[DEBUG] isCountdownActive = \(isCountdownActive), timerCount = \(timerCount)")
        timerPurpose = .captureDelay
        captureDelayTimer?.invalidate()
        captureDelayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self.timerCount -= 1
                if self.timerCount <= 0 {
                    timer.invalidate()
                    self.captureDelayTimer = nil
                    self.isCountdownActive = false
                    self.takePhoto()
                }
            }
        }
    }

    func takePhoto() {
        print("[DEBUG] takePhoto() called")
        let settings = AVCapturePhotoSettings()
        self.photoOutput.capturePhoto(with: settings, delegate: self)
        self.torchOff()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.timerPurpose = nil
        }
    }

    func switchCamera() {
        print("トリガー: カメラ切り替え")
    }

    func startSession() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleOrientationChange), name: UIDevice.orientationDidChangeNotification, object: nil)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("カメラアクセス許可済み: セッションをセットアップ開始")
            setupSession()
        case .notDetermined:
            print("カメラアクセス未決定: アクセス要求中")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("カメラアクセス許可されました: セッションをセットアップ開始")
                        self.setupSession()
                    } else {
                        print("カメラアクセスが拒否されました")
                    }
                }
            }
        default:
            print("カメラアクセスが拒否または制限されています")
        }
        handleOrientationChange()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        captureDelayTimer?.invalidate()
        gestureTimer?.invalidate()
    }

    func stopTimerOrRecording() {
        print("トリガー: タイマーまたは録画停止")
    }

    let objectWillChange = ObservableObjectPublisher()
    @Published var session: AVCaptureSession = AVCaptureSession()

    @Published var timerPurpose: TimerPurpose? = nil
    @Published var timerCount: Int = 3
    @Published var isRecording: Bool = false
    @Published var recordingDuration: Int = 0

    // Hand overlay (Vision normalized coordinates: origin at bottom-left, 0...1)
    @Published var handBoundingBox: CGRect? = nil
    @Published var handLandmarks: [CGPoint] = []

    private var videoDeviceInput: AVCaptureDeviceInput? = nil

    private let handPoseRequest = VNDetectHumanHandPoseRequest()

    // === New properties for gesture processing ===
    private var lastGesture: HandGesture? = nil
    private var lastGestureDate: Date? = nil
    private let gestureCooldown: TimeInterval = 2.0

    private var gestureTimer: Timer? = nil
    private var gestureTimerStart: Date? = nil
    private var gestureTimerDuration: TimeInterval = 0

    private func flashTorch(duration: TimeInterval) {
        // Turn on torch
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
            }
            try device.setTorchModeOn(level: 0.3)
            device.unlockForConfiguration()
        } catch {
            print("⚠️ フラッシュ制御失敗: \(error)")
            return
        }
        
        // Turn off torch after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.torchOff()
        }
    }

    private func torchOff() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            print("⚠️ フラッシュ制御失敗: \(error)")
        }
    }

    private func setupSession() {
        session.beginConfiguration()

        // 既存入力をクリア
        for input in session.inputs {
            session.removeInput(input)
        }

        // バックカメラデバイス取得
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoDeviceInput) else {
            print("カメラ入力の追加に失敗しました")
            session.commitConfiguration()
            return
        }
        session.addInput(videoDeviceInput)
        self.videoDeviceInput = videoDeviceInput

        // 動画データ出力（プレビューや録画用）
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
        // セッション開始（既に走っていなければ）
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.updatePreviewLayerOrientation()
                }
            }
        } else {
            // セッションが既に走っている場合はプレビューだけ更新
            DispatchQueue.main.async {
                self.updatePreviewLayerOrientation()
            }
        }
    }

    @objc private func handleOrientationChange() {
        let orientation = UIDevice.current.orientation
        self.deviceOrientation = orientation
        self.videoOrientation = self.avCaptureOrientation(from: orientation)
        self.updatePreviewLayerOrientation()
    }

    private func avCaptureOrientation(from deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }

    private func updatePreviewLayerOrientation() {
        DispatchQueue.main.async {
            if let connection = self.session.connections.first {
                connection.videoOrientation = self.videoOrientation
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Perform hand pose request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([handPoseRequest])
            guard let observation = handPoseRequest.results?.first else {
                DispatchQueue.main.async {
                    self.handBoundingBox = nil
                    self.handLandmarks = []
                    self.currentGesture = nil
                    self.currentGestureName = nil
                    self.resetGestureTimers()
                }
                return
            }

            // Validate confidence of landmarks for reliable detection
            guard validateHandConfidence(observation: observation) else {
                DispatchQueue.main.async {
                    self.handBoundingBox = nil
                    self.handLandmarks = []
                    self.currentGesture = nil
                    self.currentGestureName = nil
                    self.resetGestureTimers()
                }
                return
            }

            // Extract landmarks points for UI overlay
            var points: [CGPoint] = []
            do {
                let allPoints = try observation.recognizedPoints(.all)
                for (_, p) in allPoints {
                    if p.confidence > 0.3 {
                        points.append(p.location) // normalized
                    }
                }
            } catch {
                // ignore landmark extraction failure
            }
            // Calculate bounding box
            let bbox: CGRect? = {
                guard !points.isEmpty else { return nil }
                let xs = points.map { $0.x }
                let ys = points.map { $0.y }
                let minX = xs.min() ?? 0
                let minY = ys.min() ?? 0
                let maxX = xs.max() ?? 0
                let maxY = ys.max() ?? 0
                return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }()

            DispatchQueue.main.async {
                self.handBoundingBox = bbox
                self.handLandmarks = points

                // Classify gesture
                let recognizedGesture = self.classifyGesture(observation: observation)

                // If same gesture and cooldown not passed, ignore
                let now = Date()
                if let last = self.lastGesture, last == recognizedGesture,
                   let lastDate = self.lastGestureDate,
                   now.timeIntervalSince(lastDate) < self.gestureCooldown {
                    return
                }

                self.lastGesture = recognizedGesture
                self.lastGestureDate = now

                if let gesture = recognizedGesture {
                    self.processGestureWithTiming(gesture)
                } else {
                    self.currentGesture = nil
                    self.currentGestureName = nil
                    self.resetGestureTimers()
                }
            }
        } catch {
            print("Hand pose detection failed: \(error)")
        }
    }

    // Confidence validation: required landmarks are wrist, indexTip, middleTip only
    // Each confidence must be > 0.1
    // Add debug prints on low confidence landmarks
    private func validateHandConfidence(observation: VNHumanHandPoseObservation) -> Bool {
        do {
            let points = try observation.recognizedPoints(.all)
            let requiredKeys: [VNHumanHandPoseObservation.JointName] = [.wrist, .indexTip, .middleTip]
            for key in requiredKeys {
                if let point = points[key], point.confidence < 0.1 {
                    print("[debug] 信頼度低: \(key.rawValue) = \(point.confidence)")
                    return false
                }
            }
            return true
        } catch {
            return false
        }
    }

    // Classify gesture into HandGesture enum or nil
    private func classifyGesture(observation: VNHumanHandPoseObservation) -> HandGesture? {
        do {
            let thumbTip = try observation.recognizedPoint(.thumbTip)
            let indexTip = try observation.recognizedPoint(.indexTip)
            let middleTip = try observation.recognizedPoint(.middleTip)
            let ringTip = try observation.recognizedPoint(.ringTip)
            let littleTip = try observation.recognizedPoint(.littleTip)
            let wrist = try observation.recognizedPoint(.wrist)

            func distance(_ p1: VNRecognizedPoint, _ p2: VNRecognizedPoint) -> Double {
                let dx = p1.location.x - p2.location.x
                let dy = p1.location.y - p2.location.y
                return sqrt(dx * dx + dy * dy)
            }

            let openThreshold: Double = 0.18

            func isExtended(_ dist: Double) -> Bool {
                dist > openThreshold
            }

            let thumbDist = distance(thumbTip, wrist)
            let indexDist = distance(indexTip, wrist)
            let middleDist = distance(middleTip, wrist)
            let ringDist = distance(ringTip, wrist)
            let littleDist = distance(littleTip, wrist)

            let thumbExt = isExtended(thumbDist)
            let indexExt = isExtended(indexDist)
            let middleExt = isExtended(middleDist)
            let ringExt = isExtended(ringDist)
            let littleExt = isExtended(littleDist)

            //ちょき　判定ではピース
            if indexExt && middleExt {
                return .peace
            }
            //パー
            if thumbExt && indexExt && middleExt && ringExt && littleExt {
                return .open
            }
            //ぐー
            if !thumbExt && !indexExt && !middleExt && !ringExt && !littleExt {
                return .fist
            }
            return nil
        } catch {
            return nil
        }
    }

    // Process gesture with timer-based hold detection
    private func processGestureWithTiming(_ gesture: HandGesture) {
        // If a different gesture is detected while a timer is running, reset
        if currentGesture != gesture {
            if gesture == .peace {
                print("🟣 ピースを検知しました（初検出）")
            }
            print("🟣 ピース検知: timerPurposeセット前: \(String(describing: timerPurpose))")
            resetGestureTimers()
            currentGesture = gesture
            gestureTimerStart = Date()
            switch gesture {
            case .peace:
                DispatchQueue.main.async {
                    self.timerPurpose = .gestureHold
                    self.timerCount = 3
                    self.gestureTimerDuration = 3.0
                }
                print("🟣 ピース検知: timerPurpose直後: \(String(describing: timerPurpose)), timerCount: \(timerCount)")
            case .open:
                DispatchQueue.main.async {
                    self.timerPurpose = .gestureHold
                    self.timerCount = 3
                    self.gestureTimerDuration = 3.0
                }
            default:
                gestureTimerDuration = 0
            }
        }

        currentGestureName = {
            switch gesture {
            case .peace: return "ピース"
            case .open: return "パー"
            case .fist: return "グー"
            }
        }()

        // If gesture is fist and recording is active, stop recording immediately
        if gesture == .fist && isRecording {
            isRecording = false
            print("録画停止")
            resetGestureTimers()
            timerPurpose = nil
            return
        }

        // If gesture is open and not recording, start recording immediately after hold
        if (gesture == .open || gesture == .peace) {
            if gestureTimer == nil {
                // Start timer to wait gestureTimerDuration seconds
                gestureTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                    guard let self = self else{
                        timer.invalidate()
                        return
                    }
                    Task { @MainActor in
                        guard let start = self.gestureTimerStart else {
                            timer.invalidate()
                            return
                        }
                        let elapsed = Date().timeIntervalSince(start)
                        let remaining = Int(ceil(self.gestureTimerDuration - elapsed))
                        // Removed print statement here as per instruction
                        DispatchQueue.main.async {
                            self.timerCount = max(0, remaining)
                        }
                        if elapsed >= self.gestureTimerDuration {
                            timer.invalidate()
                            print("🟣 gestureTimer invalidated: elapsed=\(elapsed), timerPurpose=\(String(describing: self.timerPurpose))")
                            DispatchQueue.main.async {
                                self.timerPurpose = nil
                            }
                            
                            if gesture == .peace {
                                print("ピース判定でシャッターを切ります")
                                self.startCaptureCountdown()
                            } else if gesture == .open {
                                if !self.isRecording {
                                    self.isRecording = true
                                    print("録画開始")
                                }
                            }
                            self.resetGestureTimers()
                        }
                    }
                }
            }
        }
    }

    private func resetGestureTimers() {
        gestureTimer?.invalidate()
        gestureTimer = nil
        gestureTimerStart = nil
        timerPurpose = nil
        timerCount = 3
    }

    // Existing photo capture delegate method, unchanged
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("写真処理エラー: \(error.localizedDescription)")
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("写真データの取得または変換に失敗しました")
            return
        }

        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                } completionHandler: { success, error in
                    if success {
                        print("保存しました")
                    } else if let error = error {
                        print("写真保存エラー: \(error.localizedDescription)")
                    }
                }
            } else {
                print("写真ライブラリへのアクセスが許可されていません")
            }
        }
    }
}
