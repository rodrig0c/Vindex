import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var fadeOut = false
    @State private var fadeIn = false
    @State private var scale = 0.8

    // --- CORREÇÃO: Recebe os managers da VindexApp ---
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Image("splashscreen")
                .resizable()
                .scaledToFit()
                .frame(width: 350)
                .scaleEffect(scale)
                .opacity(fadeIn ? (fadeOut ? 0 : 1) : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.5)) {
                fadeIn = true
                scale = 1.4
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeIn(duration: 0.8)) {
                    fadeOut = true
                    scale = 1.1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    isActive = true
                }
            }
        }
        .fullScreenCover(isPresented: $isActive) {
            // --- CORREÇÃO: Passa os managers para a HomeView ---
            HomeView()
                .environmentObject(bluetoothManager)
                .environmentObject(locationManager)
        }
    }
}
