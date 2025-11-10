//
//  PairingView.swift
//  Vindex
//
//  Created by Rodrigo Costa on 14/10/25.
//


import SwiftUI

struct PairingView: View {
    @State private var pairingCode: String = ""
    @State private var error: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Parear com Guardião")
                .font(.largeTitle).bold()
            
            Text("1. Peça para seu guardião encontrar o 'VindexAlertBot' no Telegram.")
                .multilineTextAlignment(.center)
            Text("2. Peça para ele enviar o código abaixo para o bot.")
                .multilineTextAlignment(.center)
                .padding(.bottom)

            if let error = error {
                Text("Erro: \(error)")
                    .foregroundColor(.red)
            } else if pairingCode.isEmpty {
                ProgressView()
            } else {
                Text(pairingCode)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(10)
            }
            
            Button("Fechar") {
                dismiss()
            }
            .padding(.top)
        }
        .padding(30)
        .onAppear(perform: generateCode)
    }

    private func generateCode() {
        Task {
            do {
                let code = try await SupabaseManager.shared.generatePairingCode()
                DispatchQueue.main.async {
                    self.pairingCode = code
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}