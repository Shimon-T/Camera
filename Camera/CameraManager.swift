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
    private var scheduledCaptureTask: DispatchWorkItem?
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
        self.scheduledCaptureTask?.cancel()
        self.scheduledCaptureTask = nil
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
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
        guard let pixelBuffer = validateAndGetPixelBuffer(from: sampleBuffer) else { return }
        
        do {
            let observation = try performHandPoseDetection(on: pixelBuffer)
            
            guard let handObservation = observation else {
                handleNoHandDetected()
                return
            }
            
            if gestureLock {
                guard validateGestureLockState(with: handObservation) else { return }
            }
            
            guard let handPoints = validateHandConfidence(from: handObservation) else {
                handleLowConfidenceDetection()
                return
            }
            
            let gesture = classifyGesture(from: handPoints)
            processGestureWithTiming(gesture)
            
        } catch {
            print("❌ Vision error: \(error)")
        }
    }
    
    private func validateAndGetPixelBuffer(from sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard isDetecting,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return pixelBuffer
    }
    
    private func performHandPoseDetection(on pixelBuffer: CVPixelBuffer) throws -> VNHumanHandPoseObservation? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([handPoseRequest])
        return handPoseRequest.results?.first
    }
    
    private func handleNoHandDetected() {
        if self.timerPurpose == .gestureHold {
            DispatchQueue.main.async {
                self.timerPurpose = nil
                self.resetGestureState()
            }
        }
    }
    
    private func validateGestureLockState(with observation: VNHumanHandPoseObservation) -> Bool {
        do {
            let recognizedPoints = try observation.recognizedPoints(.all)
            let thumbTip = recognizedPoints[.thumbTip]
            let indexTip = recognizedPoints[.indexTip]
            let middleTip = recognizedPoints[.middleTip]
            
            if let thumb = thumbTip, let index = indexTip, let middle = middleTip,
               thumb.confidence > 0.3, index.confidence > 0.3, middle.confidence > 0.3 {
                let distance = hypot(index.location.x - middle.location.x,
                                     index.location.y - middle.location.y)
                return distance < 0.05 // fistのみ許可
            }
            return false
        } catch {
            return false
        }
    }
    
    private func validateHandConfidence(from observation: VNHumanHandPoseObservation) -> (thumb: VNRecognizedPoint, index: VNRecognizedPoint, middle: VNRecognizedPoint)? {
        do {
            let recognizedPoints = try observation.recognizedPoints(.all)
            let thumbTip = recognizedPoints[.thumbTip]
            let indexTip = recognizedPoints[.indexTip]
            let middleTip = recognizedPoints[.middleTip]
            
            if let thumb = thumbTip, let index = indexTip, let middle = middleTip,
               thumb.confidence > 0.2, index.confidence > 0.2, middle.confidence > 0.2 {
                gestureFailureCount = 0
                return (thumb: thumb, index: index, middle: middle)
            }
            return nil
        } catch {
            return nil
        }
    }
    
    private func handleLowConfidenceDetection() {
        gestureFailureCount += 1
        if gestureFailureCount >= maxGestureFailures {
            DispatchQueue.main.async {
                self.timerPurpose = nil
                self.resetGestureState()
            }
        }
        
        if self.timerPurpose == .gestureHold {
            DispatchQueue.main.async {
                self.timerPurpose = nil
                self.resetGestureState()
            }
        }
    }
    
    private func classifyGesture(from handPoints: (thumb: VNRecognizedPoint, index: VNRecognizedPoint, middle: VNRecognizedPoint)) -> String {
        let distance = hypot(handPoints.index.location.x - handPoints.middle.location.x,
                             handPoints.index.location.y - handPoints.middle.location.y)
        
        if distance < 0.05 {
            return "fist"
        } else {
            let isPeace = abs(handPoints.index.location.y - handPoints.middle.location.y) > 0.1
            return isPeace ? "peace" : "palm"
        }
    }
    
    private func processGestureWithTiming(_ gesture: String) {
        DispatchQueue.main.async {
            let now = Date()
            
            if self.currentGesture != gesture {
                self.currentGesture = gesture
                self.gestureStartTime = now
            } else if let start = self.gestureStartTime {
                let elapsed = now.timeIntervalSince(start)
                
                if elapsed >= 2.0 {
                    self.executeGestureAction(gesture)
                }
            }
        }
    }
    
    private func executeGestureAction(_ gesture: String) {
        if gesture == "fist" && self.timerPurpose == .captureDelay {
            self.cancelCurrentTimer()
            return
        }
        
        switch gesture {
        case "fist":
            self.handleFistGesture()
        case "peace":
            self.handlePeaceGesture()
        case "palm":
            self.handlePalmGesture()
        default:
            self.resetGestureState()
        }
    }
    
    private func cancelCurrentTimer() {
        self.timerPurpose = nil
        self.resetGestureState()
    }
    
    private func handleFistGesture() {
        if self.timerPurpose == .gestureHold || self.timerPurpose == .captureDelay {
            self.cancelCurrentTimer()
            return
        }
        
        print("✊ グー検出")
        self.timerTotal = 0
        self.timerCount = 0
        self.stopRecordingVideo()
        self.isRecording = false
        self.resetGestureState()
    }
    
    private func handlePeaceGesture() {
        print("✌️ ピース検出（写真撮影）")
        self.startGestureSequence { [weak self] in
            self?.capturePhoto()
        }
    }
    
    private func handlePalmGesture() {
        print("🖐 パー検出（録画開始）")
        self.startGestureSequence { [weak self] in
            self?.startRecording(after: 0)
        }
    }
    
    private func startGestureSequence(completion: @escaping () -> Void) {
        // 既存のタスクをキャンセル
        scheduledCaptureTask?.cancel()
        
        self.timerPurpose = .gestureHold
        self.startTimer(total: 2)
        self.gestureLock = true
        
        // 1.5秒後にcaptureDelayフェーズに移行
        let delayTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.timerPurpose = .captureDelay
            self.startTimer(total: 3)
            
            // 3秒後に実際の撮影/録画を実行
            let captureTask = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // タスクがキャンセルされていないかチェック
                if !(self.scheduledCaptureTask?.isCancelled ?? true) {
                    completion()
                    self.timerPurpose = nil
                    self.timerCount = 0
                    self.timerTotal = 0
                    self.resetGestureState()
                }
            }
            
            self.scheduledCaptureTask = captureTask
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: captureTask)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: delayTask)
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
