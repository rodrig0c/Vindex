// EvidenceListView.swift
// Vindex
//
// Created by Rodrigo Costa on 14/10.25.

import SwiftUI

// Tela que exibe a lista de todos os acidentes salvos localmente.
struct EvidenceListView: View {
    @State private var records: [AccidentRecord] = []
    
    var body: some View {
        NavigationView {
            // Se não houver registros, mostra uma mensagem amigável.
            if records.isEmpty {
                Text("Nenhuma evidência salva.")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .navigationTitle("Evidências Salvas")
            } else {
                List(records) { record in
                    NavigationLink(destination: EvidenceDetailView(record: record)) {
                        VStack(alignment: .leading) {
                            Text(formatarData(record.timestamp))
                                .font(.headline)
                            Text("Placa: \(record.recognizedPlate)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .navigationTitle("Evidências Salvas")
            }
        }
        .onAppear {
            // Carrega os registros do disco toda vez que a tela aparece.
            self.records = PersistenceManager.shared.loadAccidentRecords()
        }
    }
    
    // Função robusta para formatar data em português
    private func formatarData(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

}
