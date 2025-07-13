//
//  CircularTimerView.swift
//  Camera
//
//  Created by 田中志門 on 7/28/25.
//

import SwiftUI

struct CircularTimerView: View {
    var progress: Double
    var totalTime: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 12)
                .opacity(0.3)
                .foregroundColor(.white)

            Circle()
                .trim(from: 0.0, to: CGFloat(min(self.progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                .foregroundColor(.blue)
                .rotationEffect(Angle(degrees: -90))

            Text("\(Int(Double(totalTime) * (1.0 - progress)))")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.white)
        }
        .frame(width: 150, height: 150)
    }
}
