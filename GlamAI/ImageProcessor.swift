//
//  ImageProcessor.swift
//  GlamAI
//
//  Created by Grigory on 15.3.23..
//

import Foundation
import CoreImage
import Vision
import UIKit.UIImage

final class ImagesProcessor {
    
    struct ImageProcessorResult {
        let foregroundImagePath: UIImage
        let backgroundImagePath: UIImage
    }
    
    enum Error: Swift.Error {
        case failedToInitModel
        case failedToProcessImages
    }
    
    private enum ImageProcessError: Swift.Error {
        case failedToGetImage
        case failedToSegmentImage
        case failedToSeparateImage
    }
    
    func processImages(_ imageURLs: [URL]) throws -> [ImageProcessorResult] {
        let segmentationModel: segmentation_8bit
        do {
            segmentationModel = try segmentation_8bit()
        } catch {
            throw Error.failedToInitModel
        }

        var images = [ImageProcessorResult]()
        for imageURL in imageURLs {
            autoreleasepool {
                guard let result = try? processImage(url: imageURL, model: segmentationModel)
                else { return }
                images.append(.init(foregroundImagePath: result.foreground,
                                    backgroundImagePath: result.background))
            }
        }
        
        guard !images.isEmpty else { throw Error.failedToProcessImages }
        
        return images
    }
}

private extension ImagesProcessor {
    func processImage(url: URL, model: segmentation_8bit) throws -> (foreground: UIImage,
                                                                     background: UIImage) {
        guard let image = UIImage(contentsOfFile: url.path)
        else { throw ImageProcessError.failedToGetImage }
    
        let inputImage = resizeImageForModel(image)
        guard let mask = try? segmentateImage(inputImage, model: model) else {
            throw ImageProcessError.failedToSegmentImage
        }
        let improvedMask = improveMask(image: mask)
        let resizedMask = resizeMask(mask: improvedMask, to: image.size)
        let foregroundImage = try separateImageForeground(image, maskImage: resizedMask)
        let backgroundImage = try separateImageBackground(image, maskImage: resizedMask)
        return (foregroundImage, backgroundImage)
    }
    
    func resizeImageForModel(_ image: UIImage) -> UIImage {
        let resultSize = CGSize.modelInputSize
        let scale = image.size.width >= image.size.height
        ? (resultSize.width / image.size.width)
        : (resultSize.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        let targetSize = CGSize(width: width, height: height)
        
        let renderer = UIGraphicsImageRenderer(size: resultSize)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(.init(origin: .zero, size: resultSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    func resizeMask(mask: UIImage,
                    to size: CGSize) -> UIImage {
        let scale = size.width >= size.height
        ? (mask.size.width / size.width)
        : (mask.size.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        let targetSize = CGSize(width: width, height: height)
        
        let cropRect = CGRect(origin: .zero,
                              size: targetSize)
        guard let ciImage = mask.ciImage else { return mask }
        let croppedImage = UIImage(ciImage: ciImage.cropped(to: cropRect))
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            croppedImage.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    func segmentateImage(_ image: UIImage,
                         model: segmentation_8bit) throws -> UIImage {
        let imageData = image.jpegData(compressionQuality: 1) ?? Data()
        let model = try VNCoreMLModel(for: model.model)
        let request = VNCoreMLRequest(model: model)
        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([request])
        guard let result = (request.results as? [VNPixelBufferObservation])?.first?.pixelBuffer else {
            throw ImageProcessError.failedToSegmentImage
        }
        let maskImage = CIImage(cvPixelBuffer: result)

        return UIImage(ciImage: maskImage)
    }
    
    func separateImageForeground(_ image: UIImage,
                                 maskImage: UIImage) throws -> UIImage {
        try separateImage(image, with: maskImage)
    }
    
    func separateImageBackground(_ image: UIImage,
                                 maskImage: UIImage) throws -> UIImage {
        let invertedMask = try invertMask(maskImage: maskImage)
        return try separateImage(image, with: invertedMask)
    }
    
    func separateImage(_ image: UIImage,
                       with maskImage: UIImage) throws -> UIImage {
        guard let ciImage = CIImage(image: image) ?? image.ciImage,
              let ciMaskImage = CIImage(image: maskImage) ?? maskImage.ciImage
        else {
            throw ImageProcessError.failedToSeparateImage
        }
        
        let transparentImage = ciImage.settingAlphaOne(in: .zero)

        let filter = CIFilter(name: "CIBlendWithMask")
        filter?.setValue(transparentImage, forKey: kCIInputBackgroundImageKey)
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(ciMaskImage, forKey: kCIInputMaskImageKey)
        
        guard let output = filter?.outputImage else { throw ImageProcessError.failedToSeparateImage }
        return UIImage(ciImage: output)
    }
    
    func invertMask(maskImage: UIImage) throws -> UIImage {
        guard let ciImage = CIImage(image: maskImage)
        else { throw ImageProcessError.failedToSeparateImage }
        
        let filter = CIFilter(name: "CIColorInvert")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        
        guard let output = filter?.outputImage else { throw ImageProcessError.failedToSeparateImage }
        return UIImage(ciImage: output)
    }
    
    func improveMask(image: UIImage) -> UIImage {
        guard let ciIimage = image.ciImage else { return image }
        let exposure = CIFilter(name: "CIExposureAdjust")
        exposure?.setValue(ciIimage, forKey: kCIInputImageKey)
        exposure?.setValue(1, forKey: kCIInputEVKey)
        
        guard let exposureOutput = exposure?.outputImage else { return image }
        let contrast = CIFilter(name: "CIColorControls")
        contrast?.setValue(exposureOutput, forKey: kCIInputImageKey)
        contrast?.setValue(1, forKey: kCIInputContrastKey)
        
        guard let contrastOutput = contrast?.outputImage else { return image }
        let white = CIFilter(name: "CIWhitePointAdjust")
        white?.setValue(contrastOutput, forKey: kCIInputImageKey)
        white?.setValue(CIColor(cgColor: UIColor.white.cgColor), forKey: kCIInputColorKey)
        
        guard let whiteOutput = white?.outputImage else { return image }
        let result = UIImage(ciImage: whiteOutput)
        return result
    }
}

private extension CGSize {
    static let modelInputSize: CGSize = .init(width: 1024, height: 1024)
}

