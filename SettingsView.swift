import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var locationManager = LocationManager.shared
    
    // --- NOVO STATE ---
    @State private var showWifiConfigSheet = false
    
    @Environment(\.dismiss) var dismiss
    @State private var testStatusMessage: String?

    var body: some View {
        NavigationView {
            Form {
                // Seção para editar a mensagem
                Section(header: Text("Mensagem de Alerta Personalizada"), footer: Text("Esta mensagem será enviada ao seu guardião junto com sua localização.")) {
                    TextEditor(text: $settings.customAlertMessage)
                        .frame(height: 150)
                }

                // --- NOVA SEÇÃO ---
                Section(header: Text("Hardware Vindex (Pi)")) {
                    Button(action: { showWifiConfigSheet = true }) {
                        Label("Configurar Wi-Fi do Pi", systemImage: "wifi.circle.fill")
                    }
                    .foregroundColor(.primary) // Garante que não fica azul
                }
                // --- FIM DA NOVA SEÇÃO ---

                // Seção de Teste de Alerta
                Section(header: Text("Teste do Sistema")) {
                    Button(action: sendTestAlert) {
                        Label("Enviar Alerta de Teste", systemImage: "paperplane.fill")
                    }
                    
                    if let status = testStatusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Configurações")
            .navigationBarItems(trailing: Button("OK") {
                dismiss()
            })
            // --- NOVO MODIFIER ---
            .sheet(isPresented: $showWifiConfigSheet) {
                WiFiConfigView()
            }
        }
    }
    
    private func sendTestAlert() {
        guard let location = locationManager.lastKnownLocation else {
            self.testStatusMessage = "Erro: Localização indisponível. Tente novamente."
            return
        }
        
        let currentAddress = locationManager.currentAddress
        
        self.testStatusMessage = "Enviando teste para o guardião..."
        
        Task {
            do {
                try await SupabaseManager.shared.sendAccidentAlert(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    message: "[TESTE] " + settings.customAlertMessage,
                    address: currentAddress
                )
                DispatchQueue.main.async {
                    self.testStatusMessage = "✅ Teste enviado com sucesso!"
                }
            } catch {
                DispatchQueue.main.async {
                    self.testStatusMessage = "❌ Falha no envio. Erro: \(error.localizedDescription)"
                }
            }
        }
    }
}
