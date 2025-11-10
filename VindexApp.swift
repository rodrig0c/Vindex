import SwiftUI

@main
struct VindexApp: App {

    // --- CORREÇÃO: Inicializa os Singletons aqui ---
    // Isto força o BluetoothManager e o LocationManager a viver
    // durante todo o ciclo de vida da app, mesmo em segundo plano.
    @StateObject private var bluetoothManager = BluetoothManager.shared
    @StateObject private var locationManager = LocationManager.shared

    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .preferredColorScheme(.light)
                // Injeta os managers no ambiente para a HomeView os encontrar
                .environmentObject(bluetoothManager)
                .environmentObject(locationManager)
        }
    }
}
