import SwiftUI
import PhotosUI // NOVO: Importa o framework para o seletor de fotos

struct ProfileView: View {
    @State private var fullName: String = ""
    @State private var isLoading = true
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    
    // NOVO: States para gerenciar a seleção da foto
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: Image?
    @State private var avatarUrl: String?
    
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                // NOVA SEÇÃO: Para a foto de perfil
                Section {
                    HStack {
                        Spacer()
                        VStack {
                            // Exibe a imagem de perfil (carregada da URL, a selecionada ou um placeholder)
                            Group {
                                if let profileImage {
                                    profileImage
                                        .resizable()
                                } else if let avatarUrl, let url = URL(string: avatarUrl) {
                                    // AsyncImage carrega a imagem da URL de forma assíncrona
                                    AsyncImage(url: url) { image in
                                        image.resizable()
                                    } placeholder: {
                                        ProgressView() // Mostra um spinner enquanto carrega
                                    }
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .foregroundColor(.gray.opacity(0.5))
                                }
                            }
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
                            
                            // O seletor de fotos, estilizado como um botão de texto
                            PhotosPicker("Alterar Foto", selection: $selectedPhotoItem, matching: .images)
                                .padding(.top, 8)
                        }
                        Spacer()
                    }
                    .padding(.vertical)
                }
                
                Section(header: Text("Seu Nome")) {
                    if isLoading {
                        ProgressView()
                    } else {
                        TextField("Nome Completo", text: $fullName)
                    }
                }
                
                if let message = statusMessage {
                    Section { Text(message).foregroundColor(.green) }
                }
                if let error = errorMessage {
                    Section { Text(error).foregroundColor(.red) }
                }
            }
            .navigationTitle("Meu Perfil")
            .navigationBarItems(
                leading: Button("Cancelar") { dismiss() },
                trailing: Button("Salvar", action: saveProfile).disabled(isLoading)
            )
            .onAppear(perform: loadProfile)
            // NOVO: Observa mudanças na foto selecionada e inicia o upload
            .onChange(of: selectedPhotoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        // Exibe a imagem selecionada imediatamente na UI
                        if let uiImage = UIImage(data: data) {
                            profileImage = Image(uiImage: uiImage)
                        }
                        // Faz o upload para o Supabase em segundo plano
                        do {
                            try await SupabaseManager.shared.uploadProfileImage(data: data)
                        } catch {
                            errorMessage = "Falha no upload da imagem."
                        }
                    }
                }
            }
        }
    }
    
    private func loadProfile() {
        Task {
            do {
                if let profile = try await SupabaseManager.shared.fetchUserProfile() {
                    DispatchQueue.main.async {
                        self.fullName = profile.fullName ?? ""
                        self.avatarUrl = profile.avatarUrl // Carrega a URL da imagem existente
                        self.isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Perfil não encontrado."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Não foi possível carregar seu perfil."
                }
            }
        }
    }
    
    private func saveProfile() {
        isLoading = true
        Task {
            do {
                try await SupabaseManager.shared.updateUserProfile(fullName: fullName)
                DispatchQueue.main.async {
                    self.statusMessage = "Perfil salvo com sucesso!"
                    self.isLoading = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        dismiss()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Não foi possível salvar seu perfil."
                }
            }
        }
    }
}
