//
//  WiFiConfigView.swift
//  Vindex
//
//  Created by Rodrigo Costa on 09/11/25.
//


import SwiftUI

struct WiFiConfigView: View {
    @State private var ssid = ""
    @State private var password = ""
    @State private var statusMessage = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Hotspot do Telemóvel"),
                        footer: Text("Estes dados serão enviados para o Vindex Pi via Bluetooth para que ele possa aceder à internet e enviar os vídeos.")) {
                    TextField("Nome da Rede (SSID)", text: $ssid)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("Palavra-passe (Senha)", text: $password)
                }
                
                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Configurar Wi-Fi do Pi")
            .navigationBarItems(
                leading: Button("Cancelar") { dismiss() },
                trailing: Button("Enviar", action: sendWifiCredentials).disabled(ssid.isEmpty)
            )
        }
    }
    
    private func sendWifiCredentials() {
        // Formato: COMANDO;SSID;SENHA
        let command = "WIFI_CFG;\(ssid);\(password)"
        
        print("[APP] Enviando comando de config Wi-Fi...")
        BluetoothManager.shared.sendCommand(command)
        
        statusMessage = "Dados enviados! O Pi tentará ligar-se à rede '\(ssid)'."
        
        // Fecha a folha automaticamente após 3 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            dismiss()
        }
    }
}