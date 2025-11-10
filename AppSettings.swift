//
//  AppSettings.swift
//  Vindex
//
//  Created by Rodrigo Costa on 14/10/25.
//


import SwiftUI

class AppSettings: ObservableObject {
    @AppStorage("customAlertMessage") var customAlertMessage: String = "Sofri um acidente, preciso de ajuda! Esta é a minha localização."
}