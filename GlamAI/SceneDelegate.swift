//
//  SceneDelegate.swift
//  GlamAI
//
//  Created by Grigory on 15.3.23..
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(windowScene: windowScene)
        
        let imageProcessor = ImagesProcessor()
        let videoComposer = VideoComposer(directory: documentsDirectory, fileManager: .default)
        
        let templateController = TemplateController(imagesProcessor: imageProcessor,
                                                    videoComposer: videoComposer)
        
        let rootViewController = RootViewController(templateController: templateController)
        window?.rootViewController = rootViewController
        window?.makeKeyAndVisible()
    }
    
    private var documentsDirectory: URL {
        if #available(iOS 16.0, *) {
            return URL.documentsDirectory
        } else {
            return try! FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false)
        }
    }
}

