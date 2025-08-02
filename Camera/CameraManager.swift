import UIKit
import AVFoundation
import Photos
import Observation
import Combine
import Vision

@MainActor
@Observable
class CameraManager: NSObject, ObservableObject {
    private var gestureFailureCount: Int = 0
    private let maxGestureFailures: Int = 3
    enum TimerPurpose {
        case gestureHold
        case captureDelay
    }
    
    let objectWillChange = ObservableObjectPublisher()
    public var showTimer: Bool = false
    public var isRecording: Bool = false
    public var timerCount: Int = 0
    public var timerTotal: Int = 0
    public var recordingDuration: Int = 0
    public var timerPurpose: TimerPurpose? = nil
    public var testNumber = 0
    private var recordingTimer: Timer?
    private var isDetecting: Bool = false
    private var gestureLock: Bool = false
    private var gestureStartTime: Date?
    private var currentGesture: String?
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var videoDeviceInput: AVCaptureDeviceInput!
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let videoOutput = AVCaptureVideoDataOutput()
    
    override init() {
        super.init()
        configureSession()
    }
    
    private func configureSession() {
        session.beginConfiguration()
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoDeviceInput) else {
            session.commitConfiguration()
            return
        }
        session.addInput(videoDeviceInput)
        self.videoDeviceInput = videoDeviceInput
        
        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        // Add movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        // Add video output for gesture detection
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        }
        
        session.commitConfiguration()
    }
    
    func startRecording(after delay: TimeInterval) {
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingDuration = 0
            self.recordingTimer?.invalidate()
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.recordingDuration += 1
                }
            }
            self.startRecordingVideo()
        }
    }
    
    func switchCamera() {
        // TODO: Implement camera switching
    }
    
    private func startRecordingVideo() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "Recording_\(formatter.string(from: Date())).mov"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }
    
    private func stopRecordingVideo() {
        if movieOutput.isRecording {
            recordingTimer?.invalidate()
            movieOutput.stopRecording()
        }
    }
    
    private func saveVideoToLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }
    
    func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    func startHandDetection() {
        sessionQueue.async {
            self.isDetecting = true
        }
    }

    public func triggerCountdownAndCapture() {
        // For now, just capture photo directly (no countdown)
        capturePhoto()
    }
    
    public func stopTimerOrRecording() {
        if isRecording {
            stopRecordingVideo()
            isRecording = false
        } else {
            // No timer/recording to stop, do nothing or add more logic later if needed
        }
    }
    
    public func startTimer(total: Int = 3) {
        // Only set timerTotal and timerCount if timerPurpose is not nil or is already set for the same purpose
        // (To avoid overwriting timerPurpose if already set)
        if self.timerPurpose == nil || self.timerCount == 0 {
            self.timerTotal = total
            self.timerCount = total
        }

        print("▶️ タイマー開始: 合計 \(total) 秒")

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            Task { @MainActor in
                if self.timerCount > 0 {
                    self.timerCount -= 1
                    print("⏳ タイマー更新: 残り \(self.timerCount) 秒")
                } else {
                    self.timerCount = 0
                    timer.invalidate()
                    print("⏹️ タイマー終了")
                }
            }
        }
    }
    
    public func stopTimer() {
        self.timerCount = 0
    }
    
    private func resetGestureState() {
        self.currentGesture = nil
        self.gestureStartTime = nil
        self.timerPurpose = nil
        self.timerCount = 0
        self.timerTotal = 0
        self.gestureLock = false
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("動画保存失敗: \(error)")
            return
        }
        saveVideoToLibrary(url: outputFileURL)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isDetecting,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([handPoseRequest])
            guard let observation = handPoseRequest.results?.first else {
                // オレンジ（gestureHold＝ピース検知中）状態でピースが検知できなくなったら即刻中断し、タイマー非表示にする
                if self.timerPurpose == .gestureHold {
                    DispatchQueue.main.async {
                        self.timerPurpose = nil
                        self.resetGestureState()
                    }
                }
                return
            }

            if gestureLock {
                let recognizedPoints = try observation.recognizedPoints(.all)
                let thumbTip = recognizedPoints[.thumbTip]
                let indexTip = recognizedPoints[.indexTip]
                let middleTip = recognizedPoints[.middleTip]
                if let thumb = thumbTip, let index = indexTip, let middle = middleTip,
                   thumb.confidence > 0.3, index.confidence > 0.3, middle.confidence > 0.3 {
                    let distance = hypot(index.location.x - middle.location.x,
                                         index.location.y - middle.location.y)
                    let isFist = distance < 0.05
                    if !isFist { return }
                } else {
                    return
                }
            }

            let recognizedPoints = try observation.recognizedPoints(.all)

            // Simple heuristic for detecting hand openness (e.g., open palm vs closed fist)
            let thumbTip = recognizedPoints[.thumbTip]
            let indexTip = recognizedPoints[.indexTip]
            let middleTip = recognizedPoints[.middleTip]

            if let thumb = thumbTip, let index = indexTip, let middle = middleTip,
               thumb.confidence > 0.2, index.confidence > 0.2, middle.confidence > 0.2 {
                gestureFailureCount = 0  // reset failure count
            } else {
                gestureFailureCount += 1
                if gestureFailureCount >= maxGestureFailures {
                    DispatchQueue.main.async {
                        self.timerPurpose = nil
                        self.resetGestureState()
                    }
                }
                // ここもgestureHold中であれば即中断
                if self.timerPurpose == .gestureHold {
                    DispatchQueue.main.async {
                        self.timerPurpose = nil
                        self.resetGestureState()
                    }
                }
                return
            }

            let distance = hypot(indexTip!.location.x - middleTip!.location.x,
                                 indexTip!.location.y - middleTip!.location.y)

            DispatchQueue.main.async {
                let gesture: String
                if distance < 0.05 {
                    gesture = "fist"
                } else {
                    let isPeace = abs(indexTip!.location.y - middleTip!.location.y) > 0.1
                    gesture = isPeace ? "peace" : "palm"
                }

                let now = Date()
                if self.currentGesture != gesture {
                    self.currentGesture = gesture
                    self.gestureStartTime = now
                } else if let start = self.gestureStartTime {
                    let elapsed = now.timeIntervalSince(start)

                    if elapsed >= 2.0 {
                        // Added: If timerPurpose == .captureDelay and gesture is fist, cancel timer and reset state immediately
                        if gesture == "fist" && self.timerPurpose == .captureDelay {
                            self.timerPurpose = nil
                            self.resetGestureState()
                            return
                        }

                        switch gesture {
                        case "fist":
                            // If timerPurpose is gestureHold or captureDelay, cancel immediately
                            if self.timerPurpose == .gestureHold || self.timerPurpose == .captureDelay {
                                self.timerPurpose = nil
                                self.resetGestureState()
                                return
                            }
                            print("✊ グー検出")
                            self.timerTotal = 0
                            self.timerCount = 0
                            self.stopRecordingVideo()
                            self.isRecording = false
                            self.resetGestureState()
                        case "peace":
                            print("✌️ ピース検出（写真撮影）")
                            self.timerPurpose = .gestureHold
                            self.startTimer(total: 2) // UI表示は2秒に見せる
                            self.gestureLock = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                self.timerPurpose = .captureDelay
                                self.startTimer(total: 3) // for capture countdown
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                    self.capturePhoto()
                                    self.timerPurpose = nil
                                    self.timerCount = 0
                                    self.timerTotal = 0
                                    self.resetGestureState()
                                }
                            }
                        case "palm":
                            print("🖐 パー検出（録画開始）")
                            self.timerPurpose = .gestureHold
                            self.startTimer(total: 2) // UI表示は2秒に見せる
                            self.gestureLock = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                self.timerPurpose = .captureDelay
                                self.startTimer(total: 3)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                    self.startRecording(after: 0)
                                    self.timerPurpose = nil
                                    self.timerCount = 0
                                    self.timerTotal = 0
                                    self.resetGestureState()
                                }
                            }
                        default:
                            self.resetGestureState()
                            break
                        }
                    }
                }
            }
        } catch {
            print("❌ Vision error: \(error)")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                if let error = error {
                    print("❌ 写真保存失敗: \(error.localizedDescription)")
                } else {
                    print("✅ 写真を保存しました")
                }
            })
        }
    }
}

// MARK: - Photo capture helpers
extension CameraManager {
    private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

