//
//  MainViewController.swift
//  GlamAI
//
//  Created by Grigory on 15.3.23..
//

import UIKit
import AVKit

final class RootViewController: UIViewController {
    
    private let templateController: TemplateController
    
    private let applyButton = UIButton(configuration: .plain())
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    
    init(templateController: TemplateController) {
        self.templateController = templateController
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
}

private extension RootViewController {
    func setup() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(applyButton)
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            applyButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            applyButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        view.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: applyButton.bottomAnchor)
        ])
        
        activityIndicator.hidesWhenStopped = true
        
        var config = applyButton.configuration
        config?.title = "Apply Template"
        applyButton.configuration = config
        
        let applyAction = UIAction(handler: { [weak self] _ in
            self?.applyTemplate()
        })
        applyButton.addAction(applyAction, for: .touchUpInside)
    }
    
    func applyTemplate() {
        applyButton.isEnabled = false
        activityIndicator.startAnimating()
        let imageURLs = (1...8)
            .map { "pic\($0).jpeg" }
            .compactMap { Bundle.main.url(forResource: $0, withExtension: nil) }
        Task {
            do {
                let url = try await templateController.applyTemplate(with: imageURLs)
                await MainActor.run {
                    applyButton.isEnabled = true
                    activityIndicator.stopAnimating()
                    openVideo(url: url)
                }
            } catch {
                
            }
        }
    }
    
    func openVideo(url: URL) {
        let player = AVPlayer(url: url)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        self.present(playerViewController, animated: true) {
            playerViewController.player?.play()
        }
    }
}

