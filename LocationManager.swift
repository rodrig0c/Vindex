import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    @Published var currentAddress: String = "Obtendo endereço..."
    
    // NOVO: Publica a velocidade atual para a UI
    @Published var currentSpeed: Double = 0.0
    
    private var isGeocoding = false
    
    private override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation // Alta precisão para velocidade
        manager.allowsBackgroundLocationUpdates = true // Permite rodar em segundo plano
        manager.showsBackgroundLocationIndicator = true // Mostra o indicador azul
    }
    
    // --- FUNÇÃO ADICIONADA ---
    /// Aguarda pela primeira localização válida. Se já tiver uma, retorna imediatamente.
    /// Se não, aguarda o publisher @Published emitir um valor não nulo.
    public func awaitNextValidLocation() async -> CLLocationCoordinate2D {
        // 1. Se já temos uma localização, retorne imediatamente.
        if let lastKnownLocation = lastKnownLocation {
            return lastKnownLocation
        }
        
        // 2. Se não, aguarde o publisher $lastKnownLocation emitir um valor.
        print("[Location] Aguardando o primeiro sinal de GPS válido...")
        
        // Esta é uma maneira moderna (async/await) de esperar por um publisher do Combine.
        // O loop 'for await' irá pausar aqui até que $lastKnownLocation receba um valor.
        for await location in $lastKnownLocation.values {
            if let validLocation = location {
                print("[Location] Primeiro sinal de GPS recebido.")
                return validLocation // Retorna o primeiro valor não-nulo
            }
        }
        
        // Fallback (não deve ser alcançado em condições normais)
        print("[Location] A espera pelo GPS falhou ou foi interrompida.")
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    // --- FIM DA FUNÇÃO ADICIONADA ---

    public func requestLocationPermission() {
        // Pede primeiro "WhenInUse", e depois promove para "Always"
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            // Oportunidade para promover a permissão para "Sempre"
            print("[Location] Permissão 'WhenInUse' concedida. Solicitando 'Sempre'.")
            manager.requestAlwaysAuthorization()
            manager.startUpdatingLocation()
        
        case .authorizedAlways:
            // Este é o estado ideal
            print("[Location] Permissão 'Sempre' concedida. Iniciando updates.")
            manager.startUpdatingLocation()
            
        case .denied, .restricted:
            print("[Location] Permissão negada ou restrita.")
            self.currentAddress = "Permissão de localização negada."
            manager.stopUpdatingLocation()
            
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // --- ADICIONADO LOG PARA DEBUG ---
        if lastKnownLocation == nil {
            print("[Location] ✅ Primeiro update de localização recebido: \(location.coordinate)")
        }
        // --- FIM DA ADIÇÃO ---
        
        lastKnownLocation = location.coordinate
        
        // --- LÓGICA DE VELOCIDADE ---
        // A velocidade vem em metros/segundo. Convertemos para km/h.
        // Usamos max(0, ...) para evitar velocidades negativas se o GPS errar.
        let speedInMetersPerSecond = max(0, location.speed)
        let speedInKmh = speedInMetersPerSecond * 3.6
        
        // Atualiza a UI e salva na telemetria
        DispatchQueue.main.async {
            self.currentSpeed = speedInKmh
            // Adiciona o dado no TelemetryManager (que já existe)
            TelemetryManager.shared.addSpeedReading(speed: speedInKmh)
        }
        // --- FIM DA LÓGICA ---
        
        // Continua a atualizar o endereço periodicamente para a UI principal
        if !isGeocoding {
            getAddress(from: location)
        }
    }
    
    // Esta função permanece para atualizações periódicas da UI
    private func getAddress(from location: CLLocation) {
        isGeocoding = true
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                // Cria uma string de endereço mais completa
                let address = [
                    placemark.thoroughfare,     // Rua
                    placemark.subThoroughfare,  // Número
                    placemark.subLocality,      // Bairro
                    placemark.locality          // Cidade
                ].compactMap { $0 }.joined(separator: ", ")
                
                DispatchQueue.main.async {
                    self.currentAddress = address.isEmpty ? "Atualizando endereço..." : address
                }
            }
            
            // Pausa antes de tentar geocoding novamente
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                self.isGeocoding = false
            }
        }
    }

    // Função para obter o endereço sob demanda (usada na HomeView ao criar evento)
    public func fetchAddressForCurrentLocation() async -> String {
        guard let locationCoord = lastKnownLocation else {
            return "Localização indisponível"
        }
        let location = CLLocation(latitude: locationCoord.latitude, longitude: locationCoord.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                // Cria uma string de endereço mais completa
                let address = [
                    placemark.thoroughfare,     // Rua
                    placemark.subThoroughfare,  // Número
                    placemark.subLocality,      // Bairro
                    placemark.locality,         // Cidade
                    placemark.administrativeArea // Estado
                ].compactMap { $0 }.joined(separator: ", ")
                
                return address.isEmpty ? "Endereço não encontrado" : address
            }
        } catch {
            print("Erro ao buscar endereço sob demanda: \(error.localizedDescription)")
        }
        
        return "Endereço não encontrado"
    }
}
