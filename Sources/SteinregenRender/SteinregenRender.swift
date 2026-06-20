// SteinregenRender.swift
// Duenne SwiftUI-Bruecke: bettet die SpriteKit-Szene in eine View ein.

import SwiftUI
import SpriteKit

public struct GameBoardView: View {
    public let scene: GameScene

    public init(scene: GameScene) {
        self.scene = scene
    }

    public var body: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
