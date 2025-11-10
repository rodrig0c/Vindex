import SwiftUI
import MapKit
import Combine
import UserNotifications

struct HomeView: View {

    // --- CORREÇÃO (Problema 4): Recebe os managers do Ambiente ---
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @EnvironmentObject private var locationManager: LocationManager

    @StateObject private var settings = AppSettings()

    @State private var recentEvents: [AccidentRecord] = []
    @State private var userProfile: Profile?

    @State private var showGuardiansSheet = false
    @State private var showSettingsSheet = false
    @State private var showProfileSheet = false
    @State private var showTelemetrySheet = false

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )

    @State private var hasInitializedListeners = false
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if locationManager.authorizationStatus != .authorizedAlways {
                    PermissionWarningView()
                }

                Map(coordinateRegion: $region, showsUserLocation: true)
                    .frame(height: 180)
                    .overlay(
                        VStack {
                            Spacer()
                            HStack {
                                Text(locationManager.currentAddress)
                                    .font(.caption).padding(8).background(.thinMaterial).cornerRadius(10).shadow(radius: 5)
                                Spacer()
                            }
                            .padding()
                        }
                    )

                VStack(spacing: 16) {
                    HardwareStatusView()
                        .environmentObject(bluetoothManager) // Passa o manager
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
                        .padding(.horizontal)

                    Button(action: { showTelemetrySheet = true }) {
                        TelemetryStatusView(currentSpeed: locationManager.currentSpeed)
                    }
                    .tint(.primary)
                    .padding(.horizontal)

                    List {
                        Section(header: Text("EVENTOS RECENTES")) {
                            if recentEvents.isEmpty {
                                Text("Nenhum evento registrado.").foregroundColor(.secondary)
                            } else {
                                ForEach(recentEvents) { event in
                                    NavigationLink(destination: EvidenceDetailView(record: event)) {
                                        VStack(alignment: .leading) {
                                            Text(formatarDataBrasileira(event.timestamp))
                                                .font(.headline)
                                            if event.isProcessed {
                                                Text("Placa: \(event.recognizedPlate)")
                                                    .font(.caption.bold()).foregroundColor(.blue)
                                            } else {
                                                Text("Vídeo pronto para baixar (Nuvem)")
                                                    .font(.caption.italic()).foregroundColor(.orange)
                                            }
                                            Text("Arquivo: \(event.videoFileName.split(separator: "/").last.map(String.init) ?? event.videoFileName)")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    // Realce para eventos não processados E não vistos
                                    .listRowBackground( (event.isProcessed || event.hasBeenViewed) ? nil : Color.blue.opacity(0.1))
                                }
                                .onDelete(perform: deleteEvent)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .frame(maxHeight: .infinity)
                }
                .padding(.top)
                .background(Color(.systemGroupedBackground))
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showProfileSheet = true }) {
                        HStack {
                            Group {
                                if let avatarUrl = userProfile?.avatarUrl, let url = URL(string: avatarUrl) {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image { image.resizable() }
                                        else { Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.gray.opacity(0.8)) }
                                    }
                                } else {
                                    Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.gray.opacity(0.8))
                                }
                            }
                            .scaledToFill().frame(width: 40, height: 40).clipShape(Circle())

                            VStack(alignment: .leading) {
                                Text(userProfile?.fullName ?? "Meu Perfil").font(.headline)
                                if let name = userProfile?.fullName, !name.isEmpty {
                                    Text("Vindex de \(name.split(separator: " ").first ?? "")").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .tint(.primary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showGuardiansSheet = true }) { Image(systemName: "person.badge.plus") }
                        Button(action: { showSettingsSheet = true }) { Image(systemName: "gearshape.fill") }
                    }
                }
            }
            .sheet(isPresented: $showGuardiansSheet) { GuardiansView() }
            .sheet(isPresented: $showSettingsSheet) { SettingsView(settings: settings).environmentObject(locationManager) }
            .sheet(isPresented: $showProfileSheet, onDismiss: { Task { await reloadProfile() } }) { ProfileView() }
            .sheet(isPresented: $showTelemetrySheet) { TelemetryView() }
            .onAppear(perform: setup)
            .onReceive(locationManager.$lastKnownLocation.compactMap { $0 }) { coord in
                withAnimation { region.center = coord }
            }
        }
    }

    private func formatarDataBrasileira(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // --- CORREÇÃO: Ouve os DOIS subjects ---
    private func setup() {
        print("[APP] HomeView apareceu (.onAppear).")

        // Corrige o bug do JSON corrompido (Problema 3)
        if !hasInitializedListeners {
            let records = PersistenceManager.shared.loadAccidentRecords()
            if records.isEmpty {
                print("[APP] Verificação de JSON: Ficheiro OK ou vazio.")
            }
        }

        if !hasInitializedListeners {
            print("[APP] Configurando 'ouvintes' de eventos (UMA VEZ).")

            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _,_ in }

            // --- OUVINTE 1: ALERTA RÁPIDO (Problema 1) ---
            bluetoothManager.immediateCrashAlertSubject
                .receive(on: DispatchQueue.main)
                .sink {
                    print("[APP] 🚨 GATILHO DE ALERTA RÁPIDO RECEBIDO!")
                    Task(priority: .high) {
                        await self.handleImmediateAlert()
                    }
                }
                .store(in: &cancellables)

            // --- OUVINTE 2: PLACEHOLDER (DEPOIS DO UPLOAD, Problema 2) ---
            bluetoothManager.videoReadySubject
                .receive(on: DispatchQueue.main)
                .sink { videoSupabasePath in
                    print("[APP] 📹 GATILHO DE VÍDEO PRONTO RECEBIDO. Path: \(videoSupabasePath)")
                    Task(priority: .medium) {
                        await self.handleNewVideoEvidence(fileName: videoSupabasePath)
                    }
                }
                .store(in: &cancellables)

            hasInitializedListeners = true
        }

        locationManager.requestLocationPermission()
        loadRecentEvents()
        bluetoothManager.startMonitoring()

        Task {
            try? await SupabaseManager.shared.signInIfNeeded()
            await reloadProfile()
        }
    }

    private func reloadProfile() async {
        userProfile = try? await SupabaseManager.shared.fetchUserProfile()
    }

    private func loadRecentEvents() {
        self.recentEvents = PersistenceManager.shared.loadAccidentRecords()
        print("[APP] 📋 Eventos carregados: \(self.recentEvents.count)")
    }

    private func deleteEvent(at offsets: IndexSet) {
        offsets.forEach { index in
            let record = recentEvents[index]
            PersistenceManager.shared.deleteAccidentRecord(record: record)
            Task {
                try? await SupabaseManager.shared.deleteVideo(fileName: record.videoFileName)
                print("[APP] 🗑️ Vídeo de backup apagado da nuvem (se existia).")
            }
        }
        recentEvents.remove(atOffsets: offsets)
    }

    // --- FUNÇÃO DE ALERTA (RÁPIDA) ---
    private func handleImmediateAlert() async {
        print("[APP] 🚨 (Tarefa A) Iniciando envio de Alerta Imediato...")
        print("[APP] ⏳ Aguardando localização para o alerta...")
        let location = await self.locationManager.awaitNextValidLocation()
        guard location.latitude != 0 && location.longitude != 0 else {
             print("[APP] ❌ (Tarefa A) Localização indisponível. Abortando alerta.")
            return
        }

        let currentAddress = await self.locationManager.fetchAddressForCurrentLocation()

        do {
            try await SupabaseManager.shared.sendAccidentAlert(
                latitude: location.latitude,
                longitude: location.longitude,
                message: self.settings.customAlertMessage,
                address: currentAddress
            )
            print("[APP] ✅ (Tarefa A) ALERTA IMEDIATO ENVIADO COM SUCESSO!")
        } catch {
            print("[APP] ❌ (Tarefa A) FALHA CRÍTICA AO ENVIAR ALERTA: \(error.localizedDescription)")
        }
    }

    // --- FUNÇÃO DE PLACEHOLDER (LENTA) ---
    private func handleNewVideoEvidence(fileName: String) async {
        print("[APP] 💾 (Tarefa B) Iniciando criação de placeholder...")
        print("[APP] ⏳ Aguardando localização para o placeholder...")
        let location = await self.locationManager.awaitNextValidLocation()
        guard location.latitude != 0 && location.longitude != 0 else {
             print("[APP] ❌ (Tarefa B) Localização indisponível. Abortando placeholder.")
            return
        }

        let currentAddress = await self.locationManager.fetchAddressForCurrentLocation()
        let currentSpeed = self.locationManager.currentSpeed

        // --- CORREÇÃO: Erro de compilação corrigido ---
        let newRecord = AccidentRecord(
            id: UUID(),
            timestamp: Date(),
            recognizedPlate: "Não processado", // Valor inicial
            location: "\(location.latitude), \(location.longitude)",
            address: currentAddress,
            speedAtTimeOfEvent: currentSpeed, // Nome correto do parâmetro
            videoFileName: fileName,
            isProcessed: false,
            localVideoPath: nil,
            processedPlateImageName: nil,
            hasBeenViewed: false // Novo campo
        )

        PersistenceManager.shared.saveAccidentRecord(record: newRecord)

        print("[APP] ✅ (Tarefa B) Placeholder salvo no JSON. ID: \(newRecord.id)")

        // Recarrega a UI
        await MainActor.run {
            self.loadRecentEvents()
            print("[APP] ✅ (Tarefa B) Lista de eventos recarregada.")
        }
    }
}

// ... (O resto do ficheiro: FormatStyle, HardwareStatusView, TelemetryStatusView, PermissionWarningView) ...

extension FormatStyle where Self == Date.FormatStyle {
    static var localDate: Self {
        .init().day().month().year().locale(Locale(identifier: "pt_BR"))
    }

    static var localTime: Self {
        .init().hour().minute().locale(Locale(identifier: "pt_BR"))
    }
}

struct HardwareStatusView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager

    private var connectionStatus: String { bluetoothManager.connectionStatus }
    private var isMonitoring: Bool { bluetoothManager.isMonitoring }

    private var currentStatus: (text: String, color: Color, icon: String) {
        if connectionStatus.contains("Conectado") {
            if isMonitoring {
                return ("Conectado e Monitorando", .green, "checkmark.circle.fill")
            }
        }
        if connectionStatus.contains("Procurando") {
            return (connectionStatus, .blue, "magnifyingglass.circle.fill")
        }
        return (connectionStatus, .red, "xmark.circle.fill")
    }

    var body: some View {
        HStack {
            Image(systemName: currentStatus.icon)
                .foregroundColor(currentStatus.color)
            Text(currentStatus.text)
                .font(.headline)
            Spacer()
            if connectionStatus.contains("Procurando") {
                ProgressView().scaleEffect(0.8)
            }
        }
    }
}

struct TelemetryStatusView: View {
    let currentSpeed: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TELEMETRIA (VIA GPS)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(alignment: .lastTextBaseline) {
                    Text(String(format: "%.0f", currentSpeed))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("km/h")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

struct PermissionWarningView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
                .font(.title)
                .foregroundColor(.red)
            Text("Permissão de Localização Necessária")
                .font(.headline)
            Text("Para monitorar a velocidade e registrar eventos, Vindex precisa da permissão de localização 'Sempre'. Por favor, habilite nos Ajustes.")
                .font(.caption)
                .multilineTextAlignment(.center)

            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Abrir Ajustes") {
                    UIApplication.shared.open(url)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.yellow.opacity(0.85))
        .foregroundColor(.black)
    }
}
