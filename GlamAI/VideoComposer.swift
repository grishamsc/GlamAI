//
//  VideoComposer.swift
//  GlamAI
//
//  Created by Grigory on 15.3.23..
//

import Foundation
import UIKit.UIImage
import AVFoundation

final class VideoComposer {
    
    enum Error: Swift.Error {
        case noImages
        case failedToAddAudio
    }
    
    private let directory: URL
    private let fileManager: FileManager
    
    init(directory: URL,
         fileManager: FileManager) {
        self.directory = directory
        self.fileManager = fileManager
    }
    
    func composeVideo(with images: [UIImage], audio: URL?) async throws -> URL {
        guard !images.isEmpty else { throw Error.noImages }
        let outputSize = images[0].size
        let imageDuration = 0.5
        var url = try await createEmptyVideo(size: outputSize, imageDuration: imageDuration, images: images)
        if let audio {
            url = try await addAudio(movieURL: url, audioURL: audio)
        }
        return url
    }
}

private extension VideoComposer {
    func createEmptyVideo(size: CGSize, imageDuration: Double, images: [UIImage]) async throws -> URL {
        guard var image = images.first else { throw NSError(domain: "", code: 1)  }

        let pixelBufferAttributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer!
        
        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(size.width),
                            Int(size.height),
                            kCVPixelFormatType_32BGRA,
                            pixelBufferAttributes,
                            &pixelBuffer)
        CIContext().render(CIImage(image: image)!, to: pixelBuffer)
        
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                        isDirectory: true)
        let outputURL = temporaryDirectoryURL.appendingPathComponent("empty.mov")
        
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        let videoSettings = [AVVideoCodecKey: AVVideoCodecType.h264,
                             AVVideoWidthKey: size.width,
                            AVVideoHeightKey: size.height] as [String : Any]
        
        let assetWriterInput = AVAssetWriterInput(mediaType: .video,
                                                  outputSettings: videoSettings)
        let assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput,
                                                                      sourcePixelBufferAttributes: nil)
        
        assetWriter.add(assetWriterInput)
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        let duration = imageDuration * Double(images.count)
        let fps = 30
        let framesCount = 30 * duration
        var frame: Double = 0
        var imageIndex = 0
        
        while frame < framesCount {
            guard assetWriterInput.isReadyForMoreMediaData else { continue }
            let currentSecond = frame / Double(fps)
            let newImageIndex = Int(Double(currentSecond) / imageDuration)
            if imageIndex != newImageIndex {
                imageIndex = newImageIndex
                image = updateImage(image, images: images, imageIndex: imageIndex, size: image.size)
                CIContext().render(CIImage(image: image) ?? image.ciImage!, to: pixelBuffer)
            }
            
            let frameTime = CMTime(value: Int64(frame), timescale: Int32(fps))
            assetWriterAdaptor.append(pixelBuffer, withPresentationTime: frameTime)
            frame += 1
        }
        
        assetWriterInput.markAsFinished()
        
        await assetWriter.finishWriting()
        
        return outputURL
    }
    
    func addAudio(movieURL: URL, audioURL: URL) async throws -> URL {
        let videoAsset = AVURLAsset(url: movieURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first,
              let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: CMPersistentTrackID()),
              let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: CMPersistentTrackID())
        else {
            throw Error.failedToAddAudio
        }
        
        let timeRange = CMTimeRange(start: .zero, duration: videoAsset.duration)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoAssetTrack, at: .zero)
        try compositionAudioTrack.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)

        let videoSize = videoAssetTrack.naturalSize
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
          start: .zero,
          duration: composition.duration)
        videoComposition.instructions = [instruction]
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoAssetTrack)
        let transform = videoAssetTrack.preferredTransform
        
        layerInstruction.setTransform(transform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        
        guard let export = AVAssetExportSession(
          asset: composition,
          presetName: AVAssetExportPresetHighestQuality)
          else {
            throw Error.failedToAddAudio
        }
        
        let videoName = "output.mov"
        let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent(videoName)
        
        if fileManager.fileExists(atPath: exportURL.path) {
            try fileManager.removeItem(at: exportURL)
        }
        
        export.videoComposition = videoComposition
        export.outputFileType = .mov
        export.outputURL = exportURL
        
        await export.export()
        
        switch export.status {
        case .completed:
            return exportURL
        default:
            throw Error.failedToAddAudio
        }
    }
    
    func updateImage(_ image: UIImage, images: [UIImage], imageIndex: Int, size: CGSize) -> UIImage {
        guard images.count > imageIndex else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
            images[imageIndex].draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

