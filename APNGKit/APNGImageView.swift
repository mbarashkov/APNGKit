//
//  APNGImageView.swift
//  APNGKit
//
//  Created by Wei Wang on 15/8/28.
//
//  Copyright (c) 2016 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#if os(macOS)
    import Cocoa
    public typealias APNGView = NSView
    typealias CocoaImage = NSImage
#elseif os(iOS) || os(watchOS) || os(tvOS)
    import UIKit
    public typealias APNGView = UIView
    typealias CocoaImage = UIImage
#endif
    
@objc public protocol APNGImageViewDelegate {
    @objc optional func apngImageView(_ imageView: APNGImageView, didFinishPlaybackForRepeatedCount count: Int)
}

extension UIImage {
    func maskWithColor(color: UIColor) -> UIImage? {
        let maskImage = cgImage!
        
        let width = size.width
        let height = size.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)!
        
        context.clip(to: bounds, mask: maskImage)
        context.setFillColor(color.cgColor)
        context.fill(bounds)
        
        if let cgImage = context.makeImage() {
            return UIImage(cgImage: cgImage)
        } else {
            return nil
        }
    }
}

/// An APNG image view object provides a view-based container for displaying an APNG image.
/// You can control the starting and stopping of the animation, as well as the repeat count.
/// All images associated with an APNGImageView object should use the same scale. 
/// If your application uses images with different scales, they may render incorrectly.
open class APNGImageView: APNGView {
    open var maskColor:UIColor?
    
    /// The image displayed in the image view.
    /// If you change the image when the animation playing, 
    /// the animation of original image will stop, and the new one will start automatically.
    open var image: APNGImage? { // Setter should be run on main thread
        didSet {
            let animating = isAnimating
            stopAnimating()
            
            guard let image = image else {
                updateContents(nil)
                return
            }
            
            image.reset()

            let frame = image.next(currentIndex: currentFrameIndex)
            currentFrameDuration = frame.duration
            updateContents(frame.image)
            
            if animating {
                startAnimating()
            }
            
            if autoStartAnimation {
                startAnimating()
            }
        }
    }
    
    /// A Bool value indicating whether the animation is running.
    open fileprivate(set) var isAnimating: Bool
    
    /// A Bool value indicating whether the animation should be 
    /// started automatically after an image is set. Default is false.
    open var autoStartAnimation: Bool {
        didSet {
            if autoStartAnimation {
                startAnimating()
            }
        }
    }
    
    /// If true runs animation timer with option `NSRunLoopCommonModes`.
    /// ScrollView(CollectionView, TableView) items with Animated APNGImageView will not freeze during scrolling
    /// - Note: This may decrease scrolling smoothness with lot's of animations
    @available(*, deprecated, message: "This is not necessary anymore. Now APNGKit runs in a GCD-based timer.")
    open var allowAnimationInScrollView = false
    
    open weak var delegate: APNGImageViewDelegate?
    
    var timer: GCDTimer?
    var lastTimestamp: TimeInterval = 0
    var currentPassedDuration: TimeInterval = 0
    var currentFrameDuration: TimeInterval = 0
    
    var currentFrameIndex: Int = 0
    
    var repeated: Int = 0
    
    /**
    Initialize an APNG image view with the specified image.
    
    - note: This method adjusts the frame of the receiver to match the 
            size of the specified image. It also disables user interactions 
            for the image view by default.
            The first frame of image (default image) will be displayed.
    
    - parameter image: The initial APNG image to display in the image view.
    
    - returns: An initialized image view object.
    */
    public init(image: APNGImage?) {
        self.image = image
        isAnimating = false
        autoStartAnimation = false
        
        if let image = image {
            super.init(frame: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        } else {
            super.init(frame: CGRect.zero)
        }
        
        #if os(macOS)
            wantsLayer = true
        #else
            backgroundColor = UIColor.clear
            isUserInteractionEnabled = false
        #endif
        
        if let frame = image?.next(currentIndex: 0) {
            updateContents(frame.image)
        }
    }
    
    deinit {
        stopAnimating()
        
        #if os(macOS)
            // fix issue that `APNGImageView` may cause crash when deinit
            layer?.contents = nil
            wantsLayer = false
        #endif
    }

    /**
    Initialize an APNG image view with a decoder.
    
    - note: You should never call this init method from your code.
    
    - parameter aDecoder: A decoder used to decode the view from nib.
    
    - returns: An initialized image view object.
    */
    required public init?(coder aDecoder: NSCoder) {
        isAnimating = false
        autoStartAnimation = false
        super.init(coder: aDecoder)
    }
    
    /**
    Starts animation contained in the image.
    */
    open func startAnimating(frameInterval: Int = 1, back: Bool = false, completed: @escaping  (Void) -> Void = {}) {
        let mainRunLoop = RunLoop.main
        let currentRunLoop = RunLoop.current
        
        if mainRunLoop != currentRunLoop {
            performSelector(onMainThread: #selector(APNGImageView.startAnimating), with: nil, waitUntilDone: false)
            return
        }
        
        if isAnimating {
            return
        }
        
        isAnimating = true
        timer = GCDTimer(intervalInSecs: 0.016 * frameInterval)
        timer!.Event = { [weak self] _ in
            DispatchQueue.main.sync { 
                if self?.tick(back: back) == true
                {
                    completed()
                }
            }
        }
        timer!.start()
    }
    
    open func startAnimatingReverse(frameInterval: Int = 1, completed: @escaping  (Void) -> Void = {}) {
        startAnimating(frameInterval: frameInterval, back: true, completed: completed)
    }
    
    /**
    Starts animation contained in the image.
    */
    open func stopAnimating() {
        let mainRunLoop = RunLoop.main
        let currentRunLoop = RunLoop.current
        
        if mainRunLoop != currentRunLoop {
            performSelector(onMainThread: #selector(APNGImageView.stopAnimating), with: nil, waitUntilDone: false)
            return
        }
        
        if !isAnimating {
            return
        }
        
        isAnimating = false
        repeated = 0
        lastTimestamp = 0
        currentPassedDuration = 0
        currentFrameIndex = 0
        
        timer = nil
    }
    
    open func pauseAnimating() {
        let mainRunLoop = RunLoop.main
        let currentRunLoop = RunLoop.current
        
        if mainRunLoop != currentRunLoop {
            performSelector(onMainThread: #selector(APNGImageView.pauseAnimating), with: nil, waitUntilDone: true)
            return
        }
        
        if !isAnimating {
            return
        }
        
        isAnimating = false
        
        timer?.invalidate()
        timer = nil
    }
    
    func tick(back: Bool = false) {
        guard let image = image else {
            return
        }
        
        let timestamp = CACurrentMediaTime()
        if lastTimestamp == 0 {
            lastTimestamp = timestamp
            if(back)
            {
                currentFrameIndex = image.frameCount - 1
            }
            else
            {
                return false
            }
        }
        
        let elapsedTime = timestamp - lastTimestamp
        lastTimestamp = timestamp
        
        currentPassedDuration += elapsedTime
        
        if currentPassedDuration >= currentFrameDuration {
            let easyBackwards = 1 + Int(currentFrameIndex * currentFrameIndex / (13 * 13))
            currentFrameIndex = currentFrameIndex + (back ? -easyBackwards : 1)
            
            var ended = back? currentFrameIndex < 0 : currentFrameIndex == image.frameCount
            
            if ended {
                
                delegate?.apngImageView?(self, didFinishPlaybackForRepeatedCount: repeated)
                
                // If user set image to `nil`, do not render anymore.
                guard let _ = self.image else { return }
                
                currentFrameIndex = 0
                repeated = repeated + 1
                
                if image.repeatCount != RepeatForever && repeated >= image.repeatCount {
                    stopAnimating()
                    // Stop in the last frame
                    return
                }
                
                // Only the first frame could be hidden.
                if image.firstFrameHidden {
                    // Skip the first frame
                    _ = image.next(currentIndex: 0)
                    currentFrameIndex = 1
                }
            }
            
            currentPassedDuration = currentPassedDuration - currentFrameDuration
            
            let frame = image.next(currentIndex: currentFrameIndex)
            currentFrameDuration = frame.duration
            if(maskColor == nil)
            {
                updateContents(frame.image)
            }
            else
            {
                updateContents(frame.image?.maskWithColor(color: maskColor!))
            }
        }
        return false
    }
    
    func updateContents(_ image: CocoaImage?) {
        
        let currentImage: CGImage?
        
        #if os(macOS)
            if layer?.contents != nil {
                currentImage = (layer?.contents as! CGImage)
            } else {
                currentImage = nil
            }
            
            let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            
            if cgImage !== currentImage {
                layer?.contents = cgImage
            }
        #else
            if layer.contents != nil {
                currentImage = (layer.contents as! CGImage)
            } else {
                currentImage = nil
            }
            
            let cgImage = image?.cgImage
            
            if cgImage !== currentImage {
                layer.contents = cgImage
                if let image = image {
                    layer.contentsScale = image.scale
                }
            }
        #endif
    }
}

