//
//  TemplateController.swift
//  GlamAI
//
//  Created by Grigory on 15.3.23..
//

import Foundation
import UIKit.UIImage
import Vision
import AVFoundation

struct ProcessedImage {
    let name: String
    let foregroundPath: URL
    let backgroundPath: URL
}

final class TemplateController {
    
    private let imagesProcessor: ImagesProcessor
    private let videoComposer: VideoComposer
    
    init(imagesProcessor: ImagesProcessor,
         videoComposer: VideoComposer) {
        self.imagesProcessor = imagesProcessor
        self.videoComposer = videoComposer
    }
    
    enum Error: Swift.Error {
        case failedToCreateVideo
    }
    
    func applyTemplate(with imageURLs: [URL]) async throws -> URL {
        do {
            let firstImage = UIImage(contentsOfFile: imageURLs[0].path)
            let result = try self.imagesProcessor.processImages(Array(imageURLs[1...]))
            let images = ([firstImage] + result.flatMap { [$0.foregroundImagePath, $0.backgroundImagePath] })
                .compactMap { $0 }
            
            let url = try await self.videoComposer.composeVideo(with: images, audio: Bundle.main.url(forResource: "music", withExtension: "aac"))
            return url
        } catch {
            throw Error.failedToCreateVideo
        }
    }
}

