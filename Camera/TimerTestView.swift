//
//  Timer.swift
//  Camera
//
//  Created by 田中志門 on 7/28/25.
//

import SwiftUI

struct TimerTestView: View {
    @State private var timeRemaining = 3
    @State private var totalTime = 3
    @State private var timerActive = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if timerActive {
                CircularTimerComponent(
                    progress: 1.0 - Double(timeRemaining) / Double(max(totalTime, 1)),
                    totalTime: totalTime
                )
                .frame(width: 150, height: 150)
                .transition(.scale)
            }

            VStack {
                Spacer()
                Button("スタート") {
                    timeRemaining = totalTime
                    timerActive = true
                    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                        if timeRemaining > 0 {
                            timeRemaining -= 1
                        } else {
                            timer.invalidate()
                            timerActive = false
                        }
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(10)
                .padding(.bottom, 40)
            }
        }
    }
}

struct CircularTimerComponent: View {
    var progress: Double
    var totalTime: Int
    var color: Color = .blue

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 12)
                .opacity(0.3)
                .foregroundColor(.white)

            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                .foregroundColor(color)
                .rotationEffect(Angle(degrees: -90))

            Text("\(Int(Double(totalTime) * (1.0 - progress)))")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.white)
        }
        .frame(width: 150, height: 150)
    }
}
