// Guardian.swift
import Foundation

struct Guardian: Codable, Identifiable {
    let id: Int
    let chatId: Int
    var telegramUsername: String? // NOVA PROPRIEDADE

    enum CodingKeys: String, CodingKey {
        case id
        case chatId = "chat_id"
        case telegramUsername = "telegram_username"
    }
}
