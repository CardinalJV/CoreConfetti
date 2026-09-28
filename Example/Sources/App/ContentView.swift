//
//  ContentView.swift
//  CoreConfetti
//

import SwiftUI
import CoreConfetti

/// The whole demo: one button, the confetti it fires, and a sheet for turning
/// the knobs that sheet exposes — count, colours, symbols.
///
/// Everything worth turning lives on `options`; the rest of `ConfettiSettings`
/// keeps its default. `trigger` is any `Equatable` value: each change fires a
/// volley, so a counter is the simplest thing to hand it.
struct ContentView: View {

    @State private var trigger = 0
    @State private var options = ConfettiOptions()
    @State private var isShowingOptions = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Button {
                    trigger += 1
                } label: {
                    Label("Fire", systemImage: "party.popper.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                // The cannon fires from the middle of whatever it is attached to,
                // and never takes part in that view's layout.
                .confettiCannon(trigger: trigger, settings: options.settings)

                Button {
                    isShowingOptions = true
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .tint(.purple)
            }
        }
        .sheet(isPresented: $isShowingOptions) {
            ConfettiOptionsSheet(options: options)
        }
    }
}

#Preview {
    ContentView()
}
