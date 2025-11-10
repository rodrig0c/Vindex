import Foundation
import Supabase

struct AlertParams: Encodable {
    let latitude: Double
    let longitude: Double
    let message: String
    let address: String?
}

class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient

    private init() {
        let supabaseURL = URL(string: "https://olamjwkznwiljwpbqgti.supabase.co")!
        // Esta é a sua chave 'anon' (anónima), que é pública e segura para o app.
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9sYW1qd2t6bndpbGp3cGJxZ3RpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA0NjIwMDYsImV4cCI6MjA3NjAzODAwNn0.DoHsIclwL0XcOng8Cvtv2ljwnHvc35oF16HPZuMFR_Y"
        
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey,
            options: SupabaseClientOptions(
                auth: .init(storage: KeychainSessionStorage())
            )
        )
    }

    func signInIfNeeded() async throws {
        do {
            _ = try await client.auth.session
            print("DEBUG: Sessão existente restaurada com sucesso.")
        } catch {
            print("DEBUG: Sessão inválida ou ausente detectada. Limpando e criando nova sessão anônima...")
            try await client.auth.signOut()
            _ = try await client.auth.signInAnonymously()
            print("DEBUG: Nova sessão anônima criada com sucesso.")
        }
    }

    func generatePairingCode() async throws -> String {
        let result: [String: String] = try await client.functions.invoke("generate-code")
        return result["pairing_code"] ?? ""
    }

    func sendAccidentAlert(latitude: Double, longitude: Double, message: String, address: String?) async throws {
        let params = AlertParams(latitude: latitude, longitude: longitude, message: message, address: address)
        _ = try await client.functions.invoke("send-alert", options: .init(body: params))
    }

    func fetchUserProfile() async throws -> Profile? {
        let user = try await client.auth.user()
        let profile: Profile = try await client.from("profiles")
            .select()
            .eq("id", value: user.id)
            .single()
            .execute()
            .value
        return profile
    }

    func updateUserProfile(fullName: String) async throws {
        let user = try await client.auth.user()
        try await client.from("profiles")
            .update(["full_name": fullName])
            .eq("id", value: user.id)
            .execute()
    }

    func fetchGuardians() async throws -> [Guardian] {
        let guardians: [Guardian] = try await client.from("guardians")
            .select()
            .execute()
            .value
        return guardians
    }

    func deleteGuardian(id: Int) async throws {
        try await client.from("guardians")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    func uploadProfileImage(data: Data) async throws {
        let user = try await client.auth.user()
        let filePath = "\(user.id)/profile.jpg"
        
        _ = try await client.storage
            .from("profile-pictures")
            .upload(path: filePath, file: data, options: .init(cacheControl: "3600", upsert: true))
        
        let response = try await client.storage
            .from("profile-pictures")
            .getPublicURL(path: filePath)
        
        try await client.from("profiles")
            .update(["avatar_url": response.absoluteString])
            .eq("id", value: user.id)
            .execute()
    }
    
    // --- NOVA FUNÇÃO 1: BAIXAR VÍDEO ---
    func downloadVideo(fileName: String) async throws -> Data {
        print("[Supabase] Baixando vídeo: \(fileName)...")
        
        // "fileName" será algo como "public/evento_123.h264"
        let fileData = try await client.storage
            .from("videos") // O nome do seu bucket
            .download(path: fileName)
        
        print("[Supabase] Download concluído: \(fileData.count) bytes")
        return fileData
    }
    
    // --- NOVA FUNÇÃO 2: APAGAR VÍDEO ---
    func deleteVideo(fileName: String) async throws {
        print("[Supabase] Apagando vídeo da nuvem: \(fileName)...")
        
        _ = try await client.storage
            .from("videos") // O nome do seu bucket
            .remove(paths: [fileName])
        
        print("[Supabase] ✅ Vídeo apagado da nuvem com sucesso.")
    }
}
