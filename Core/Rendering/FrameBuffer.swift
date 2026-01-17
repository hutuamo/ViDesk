import Foundation
import Metal
import CoreGraphics

/// 帧缓冲区管理
/// 负责存储和管理远程桌面的像素数据
final class FrameBuffer: @unchecked Sendable {
    let width: Int
    let height: Int
    let bytesPerPixel: Int
    let bytesPerRow: Int

    private var buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private let lock = NSLock()

    /// 脏区域列表 (需要更新的区域)
    private var dirtyRegions: [CGRect] = []

    init(width: Int, height: Int, bytesPerPixel: Int = 4) {
        self.width = width
        self.height = height
        self.bytesPerPixel = bytesPerPixel
        self.bytesPerRow = width * bytesPerPixel
        self.bufferSize = height * bytesPerRow

        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        self.buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        buffer.deallocate()
    }

    /// 获取缓冲区指针
    var pointer: UnsafePointer<UInt8> {
        UnsafePointer(buffer)
    }

    /// 获取可变缓冲区指针
    var mutablePointer: UnsafeMutablePointer<UInt8> {
        buffer
    }

    /// 更新指定区域
    func update(from source: UnsafePointer<UInt8>, region: CGRect) {
        lock.lock()
        defer { lock.unlock() }

        let x = Int(region.origin.x)
        let y = Int(region.origin.y)
        let w = Int(region.size.width)
        let h = Int(region.size.height)

        // 边界检查
        guard x >= 0, y >= 0, x + w <= width, y + h <= height else { return }

        // 逐行复制
        for row in 0..<h {
            let srcOffset = ((y + row) * width + x) * bytesPerPixel
            let dstOffset = srcOffset

            memcpy(buffer.advanced(by: dstOffset),
                   source.advanced(by: srcOffset),
                   w * bytesPerPixel)
        }

        dirtyRegions.append(region)
    }

    /// 更新整个缓冲区
    func updateFull(from source: UnsafePointer<UInt8>) {
        lock.lock()
        defer { lock.unlock() }

        memcpy(buffer, source, bufferSize)
        dirtyRegions = [CGRect(x: 0, y: 0, width: width, height: height)]
    }

    /// 获取并清空脏区域
    func popDirtyRegions() -> [CGRect] {
        lock.lock()
        defer { lock.unlock() }

        let regions = dirtyRegions
        dirtyRegions.removeAll()
        return regions
    }

    /// 检查是否有脏区域
    var hasDirtyRegions: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !dirtyRegions.isEmpty
    }

    /// 将缓冲区数据复制到 Metal 纹理
    func copyToTexture(_ texture: MTLTexture) {
        lock.lock()
        defer { lock.unlock() }

        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))

        texture.replace(region: region,
                        mipmapLevel: 0,
                        withBytes: buffer,
                        bytesPerRow: bytesPerRow)
    }

    /// 将指定区域复制到 Metal 纹理
    func copyRegionToTexture(_ texture: MTLTexture, region: CGRect) {
        lock.lock()
        defer { lock.unlock() }

        let x = Int(region.origin.x)
        let y = Int(region.origin.y)
        let w = Int(region.size.width)
        let h = Int(region.size.height)

        guard x >= 0, y >= 0, x + w <= width, y + h <= height else { return }

        let mtlRegion = MTLRegion(origin: MTLOrigin(x: x, y: y, z: 0),
                                  size: MTLSize(width: w, height: h, depth: 1))

        let sourceOffset = (y * width + x) * bytesPerPixel

        texture.replace(region: mtlRegion,
                        mipmapLevel: 0,
                        withBytes: buffer.advanced(by: sourceOffset),
                        bytesPerRow: bytesPerRow)
    }

    /// 创建 CGImage 用于调试
    func createCGImage() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(data: buffer,
                                       width: width,
                                       height: height,
                                       bitsPerComponent: 8,
                                       bytesPerRow: bytesPerRow,
                                       space: colorSpace,
                                       bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }

        return context.makeImage()
    }
}

/// 帧缓冲区池
/// 用于三重缓冲以减少延迟
final class FrameBufferPool {
    private var buffers: [FrameBuffer]
    private var currentIndex: Int = 0
    private let lock = NSLock()

    init(width: Int, height: Int, bytesPerPixel: Int = 4, count: Int = 3) {
        buffers = (0..<count).map { _ in
            FrameBuffer(width: width, height: height, bytesPerPixel: bytesPerPixel)
        }
    }

    /// 获取下一个可用缓冲区
    func nextBuffer() -> FrameBuffer {
        lock.lock()
        defer { lock.unlock() }

        let buffer = buffers[currentIndex]
        currentIndex = (currentIndex + 1) % buffers.count
        return buffer
    }

    /// 调整所有缓冲区大小
    func resize(width: Int, height: Int, bytesPerPixel: Int = 4) {
        lock.lock()
        defer { lock.unlock() }

        buffers = buffers.map { _ in
            FrameBuffer(width: width, height: height, bytesPerPixel: bytesPerPixel)
        }
        currentIndex = 0
    }
}
