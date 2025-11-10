//
//  Profile.swift
//  Vindex
//
//  Created by Rodrigo Costa on 14/10/25.
//


// Profile.swift
import Foundation

// Profile.swift
struct Profile: Codable {
    let id: UUID
    var fullName: String?
    var avatarUrl: String? // NOVA PROPRIEDADE

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case avatarUrl = "avatar_url" // NOVO
    }
}
