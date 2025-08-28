//
//  CameraPreviewView.swift
//  Camera
//
//  Created by 田中志門 on 7/12/25.
//

import SwiftUI

struct CameraPreviewView: View {
    @ObservedObject var cameraManager: CameraManager
    @State private var smoothProgressTime: TimeInterval = 0.0
    @State private var timer: Timer?
    
    var body: some View {
        let timerOverlayOpacity = (cameraManager.timerPurpose == .gestureHold || cameraManager.timerPurpose == .captureDelay) ? 1.0 : 0.0
        
        ZStack {
            // カメラ映像の表示 with hand landmarks overlay
            CameraView(session: cameraManager.session)
                .ignoresSafeArea()
                .overlay(
                    GeometryReader { geo in
                        ZStack {
                            ForEach(cameraManager.handLandmarks.indices, id: \.self) { index in
                                let point = cameraManager.handLandmarks[index]
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .position(
                                        x: point.x * geo.size.width,
                                        y: (1 - point.y) * geo.size.height
                                    )
                            }
                        }
                    }
                )
            
            // カメラ画面中央上部にcurrentGesture表示
            if let gesture = cameraManager.currentGesture {
                Text(gesture)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                    .position(x: UIScreen.main.bounds.width / 2, y: 80)
                    .zIndex(999)
            }
            
            // カウントダウン関連デバッグプリント
            Text("") // Dummy invisible view to prevent view builder error
                .onAppear {
                    print("[View] isCountdownActive before if: \(cameraManager.isCountdownActive)")
                }
            
            // カウントダウン表示
            if cameraManager.isCountdownActive {
                CountdownNumberView()
                    .onAppear {
                        print("[View] CountdownNumberView appeared")
                    }
            }
            
            // 録画中インジケーター
            if cameraManager.isRecording {
                VStack {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("録画中: \(cameraManager.recordingDuration) 秒")
                            .foregroundColor(.white)
                            .bold()
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.horizontal)
            }
            
            // テスト用の手動操作ボタン
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Button("📸 撮影開始（テスト）") {
                        print("[TEST] テストボタンが押されました")
                        cameraManager.takePhoto()
                    }
                    Button("🔄 カメラ切替") {
                        cameraManager.switchCamera()
                    }
                    Button("🛑 停止") {
                        cameraManager.stopTimerOrRecording()
                    }
                    
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .cornerRadius(12)
                .padding(.bottom, 30)
            }
        }
        .animation(.spring(), value: cameraManager.timerPurpose)
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .onChange(of: cameraManager.timerPurpose) { newValue in
            print("[DEBUG] timerPurpose が変更されました: ", newValue as Any)
            timer?.invalidate()
            timer = nil
            if newValue != nil {
                smoothProgressTime = 0.0
                timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
                    DispatchQueue.main.async {
                        if smoothProgressTime < 3.0 {
                            smoothProgressTime += 0.02
                        } else {
                            timer?.invalidate()
                            timer = nil
                        }
                    }
                }
            }
            if newValue == .gestureHold {
                print("🟠 検出タイマー開始: 残り \(cameraManager.timerCount) 秒")
                print("[DEBUG] ピース検知時のタイマーopacity =", timerOverlayOpacity)
            } else if newValue == .captureDelay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🟢 撮影タイマー開始: 残り \(cameraManager.timerCount) 秒")
                }
                print("[DEBUG] シャッター時のタイマーopacity =", timerOverlayOpacity)
            }
        }
    }
}
