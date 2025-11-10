import Foundation
import CoreBluetooth
import UIKit
import Combine
import UserNotifications

private let VINDEX_SERVICE_UUID = CBUUID(string: "0000ffe0-0000-1000-8000-00805f9b34fb")
private let VINDEX_NOTIFY_CHAR_UUID = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb")
private let VINDEX_WRITE_CHAR_UUID = CBUUID(string: "0000ffe2-0000-1000-8000-00805f9b34fb")

class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    @Published var connectionStatus = "Iniciando..."
    @Published var isMonitoring = true

    let immediateCrashAlertSubject = PassthroughSubject<Void, Never>()
    let videoReadySubject = PassthroughSubject<String, Never>()

    private var centralManager: CBCentralManager!
    private var vindexPeripheral: CBPeripheral?
    private var vindexNotifyCharacteristic: CBCharacteristic?
    private var vindexWriteCharacteristic: CBCharacteristic?
    
    private let videoReadyMarker = "VIDEO_READY;"
    private let crashAlertMarker = "CRASH_ALERT"
    private let wifiStatusMarker = "WIFI_CONNECTED"

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        print("[BLE] BluetoothManager inicializado - Aguardando Bluetooth...")
    }

    func startMonitoring() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth Desligado"
            print("[BLE] ❌ Bluetooth não está ligado")
            return
        }
        
        if let vindexPeripheral = vindexPeripheral, vindexPeripheral.state == .connected {
            print("[BLE] ✅ Já está conectado ao Vindex. Monitoramento continua.")
            DispatchQueue.main.async {
                self.isMonitoring = true
                self.connectionStatus = "Conectado e Monitorando"
            }
            return
        }
        
        if centralManager.isScanning {
            print("[BLE] ⚠️ Já está escaneando...")
            return
        }
        
        print("[BLE] 🔍 Iniciando busca por Vindex...")
        connectionStatus = "Procurando Vindex..."
        
        // --- CORREÇÃO (Problema 4): Scan em fundo ---
        // Em vez de 'nil', procuramos especificamente pelo nosso UUID.
        // Isto permite ao iOS acordar a app em segundo plano.
        centralManager.scanForPeripherals(withServices: [VINDEX_SERVICE_UUID], options: nil)
    }
    
    func stopMonitoring() {
        if centralManager.isScanning {
            centralManager.stopScan()
            print("[BLE] ⏹️ Parou de escanear")
        }
    }
    
    func sendCommand(_ command: String) {
        guard let peripheral = vindexPeripheral,
              let characteristic = vindexWriteCharacteristic,
              let data = command.data(using: .utf8) else {
            print("[BLE] ❌ Não é possível enviar comando: BLE não está pronto")
            return
        }
        
        print("[BLE] ➡️ Enviando comando: \(command)")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

// MARK: - Delegates do Central Manager
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionStatus = "Bluetooth Ligado"
            print("[BLE] ✅ Bluetooth ligado - Iniciando monitoramento")
            startMonitoring()
        case .poweredOff:
            connectionStatus = "Bluetooth Desligado"
            print("[BLE] ❌ Bluetooth desligado")
        case .resetting:
            connectionStatus = "Bluetooth Reiniciando"
        case .unauthorized:
            connectionStatus = "Bluetooth Não Autorizado"
        case .unsupported:
            connectionStatus = "Bluetooth Não Suportado"
        case .unknown:
            connectionStatus = "Estado Bluetooth Desconhecido"
        @unknown default:
            connectionStatus = "Estado Bluetooth Desconhecido"
        }
    }

    // --- CORREÇÃO (Problema 4): 'didDiscover' simplificado ---
    // Uma vez que SÓ procuramos pelo UUID, qualquer dispositivo
    // encontrado aqui é (provavelmente) o nosso.
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Vindex (Sem Nome)"
        print("[BLE] 🔍 Encontrado: \(name) (RSSI: \(RSSI))")
        
        // Se já temos um periférico, ignoramos.
        // Se não, este é o nosso.
        guard vindexPeripheral == nil else {
            return
        }
        
        print("[BLE] 🎯 Vindex encontrado (\(name))! Conectando...")
        centralManager.stopScan()
        vindexPeripheral = peripheral
        vindexPeripheral?.delegate = self
        connectionStatus = "Conectando ao \(name)..."
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] ✅ Conectado ao Vindex!")
        connectionStatus = "Conectado - Buscando serviços..."
        DispatchQueue.main.async { self.isMonitoring = true }
        peripheral.discoverServices([VINDEX_SERVICE_UUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLE] ⚠️ Desconectado do Vindex: \(error?.localizedDescription ?? "Sem erro")")
        vindexPeripheral = nil
        vindexNotifyCharacteristic = nil
        vindexWriteCharacteristic = nil
        connectionStatus = "Desconectado - Reconectando..."
        
        // Tenta reconectar imediatamente
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Reduzido para 1s
            self.startMonitoring()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BLE] ❌ Falha na conexão: \(error?.localizedDescription ?? "Sem erro")")
        connectionStatus = "Falha na conexão"
        vindexPeripheral = nil // Limpa o periférico falhado
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.startMonitoring()
        }
    }
}

// MARK: - Delegates do Peripheral
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == VINDEX_SERVICE_UUID {
                print("[BLE] ✅ Serviço Vindex encontrado! Buscando características...")
                peripheral.discoverCharacteristics([VINDEX_NOTIFY_CHAR_UUID, VINDEX_WRITE_CHAR_UUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == VINDEX_NOTIFY_CHAR_UUID {
                print("[BLE] ✅ Característica Notify encontrada!")
                vindexNotifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == VINDEX_WRITE_CHAR_UUID {
                print("[BLE] ✅ Característica Write encontrada!")
                vindexWriteCharacteristic = characteristic
            }
        }
        if vindexNotifyCharacteristic != nil && vindexWriteCharacteristic != nil {
            connectionStatus = "Conectado e Monitorando"
            print("[BLE] 🎯 BLE totalmente configurado - Pronto para uso!")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.isNotifying {
            print("[BLE] 🔔 Notificações ativadas para \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value,
              let message = String(data: data, encoding: .utf8) else {
            print("[BLE] ⚠️ Dados vazios ou inválidos")
            return
        }
        
        print("[BLE] 📦 Mensagem recebida: \(message)")

        if message.starts(with: videoReadyMarker) {
            let videoSupabasePath = message.replacingOccurrences(of: videoReadyMarker, with: "")
            print("[BLE] 🚨 VÍDEO PRONTO NA NUVEM! Path: \(videoSupabasePath)")
            DispatchQueue.main.async {
                if !videoSupabasePath.isEmpty {
                    self.videoReadySubject.send(videoSupabasePath)
                }
            }
        
        } else if message == crashAlertMarker {
            print("[BLE] 🚨 ALERTA RÁPIDO DE CRASH RECEBIDO!")
            DispatchQueue.main.async {
                self.immediateCrashAlertSubject.send()
                self.triggerLocalNotification(title: "🚨 Acidente Detectado!",
                                         body: "A enviar alerta para os guardiões. O vídeo está a ser processado.")
            }

        } else if message == wifiStatusMarker {
            print("[BLE] ✅ Pi confirmou conexão Wi-Fi (Hotspot).")
            triggerLocalNotification(title: "Vindex Conectado",
                                     body: "O Pi está online e pronto para gravar.")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            print("[BLE] ❌ Erro ao enviar comando: \(error!.localizedDescription)")
        } else {
            print("[BLE] ✅ Comando enviado com sucesso")
        }
    }
    
    private func triggerLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[APP] ❌ Falha ao agendar notificação local: \(error.localizedDescription)")
            } else {
                print("[APP] 🔔 Notificação local agendada com sucesso.")
            }
        }
    }
}
