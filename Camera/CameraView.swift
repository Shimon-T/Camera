//
//  CameraView.swift
//  Camera
//
//  Created by 田中志門 on 7/12/25.
//

import SwiftUI
import AVFoundation

// UIView 上で AVFoundation のカメラプレビューを表示するクラス
class CameraPreviewUIView: UIView {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    override init(frame: CGRect) {
        self.previewLayer = AVCaptureVideoPreviewLayer()
        super.init(frame: frame)
        self.previewLayer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(previewLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// SwiftUI でカメラプレビューを扱うラッパー
struct CameraView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}
