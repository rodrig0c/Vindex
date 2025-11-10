//
//  GuardiansView.swift
//  Vindex
//
//  Created by Rodrigo Costa on 14/10/25.
//


import SwiftUI

struct GuardiansView: View {
    @State private var guardians: [Guardian] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var showPairingSheet = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Carregando guardiões...")
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                } else if guardians.isEmpty {
                    Text("Nenhum guardião configurado.")
                        .font(.title2)
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(guardians) { guardian in
                            // ATUALIZADO: Usa o nome do Telegram ou o ID como fallback
                            let guardianName = guardian.telegramUsername ?? "ID: \(guardian.chatId)"
                            Label(guardianName, systemImage: "person.fill.checkmark")
                        }
                        .onDelete(perform: deleteGuardian)
                    }
                }
            }
            .navigationTitle("Meus Guardiões")
            .navigationBarItems(
                leading: Button("Fechar") { dismiss() },
                trailing: Button(action: { showPairingSheet = true }) {
                    Image(systemName: "plus")
                }
            )
            .onAppear(perform: loadGuardians)
            .sheet(isPresented: $showPairingSheet, onDismiss: loadGuardians) {
                // A tela de pareamento agora é apresentada a partir daqui
                PairingView()
            }
        }
    }
    
    private func loadGuardians() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetchedGuardians = try await SupabaseManager.shared.fetchGuardians()
                DispatchQueue.main.async {
                    self.guardians = fetchedGuardians
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Não foi possível carregar a lista de guardiões."
                    self.isLoading = false
                    print("DEBUG: Erro ao buscar guardiões: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func deleteGuardian(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        let guardianToDelete = guardians[index]
        
        Task {
            do {
                try await SupabaseManager.shared.deleteGuardian(id: guardianToDelete.id)
                // Remove da lista local para a UI atualizar instantaneamente
                DispatchQueue.main.async {
                    guardians.remove(atOffsets: offsets)
                }
            } catch {
                print("DEBUG: Erro ao deletar guardião: \(error.localizedDescription)")
                // Poderíamos mostrar um alerta de erro aqui
            }
        }
    }
}
