import Foundation
import Metal
import MetalKit
import simd

/// Metal 渲染引擎
/// 负责将远程桌面帧缓冲区渲染到屏幕
final class MetalRenderer: NSObject, MTKViewDelegate {
    // MARK: - 属性

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?

    private var texture: MTLTexture?
    private var vertexBuffer: MTLBuffer?

    private var textureWidth: Int = 0
    private var textureHeight: Int = 0

    /// 缩放模式
    var scaleMode: ScaleMode = .fit {
        didSet {
            updateVertexBuffer()
        }
    }

    /// 帧缓冲区
    var frameBuffer: FrameBuffer? {
        didSet {
            if let fb = frameBuffer {
                createTexture(width: fb.width, height: fb.height)
            }
        }
    }

    /// 视图尺寸
    private var viewSize: CGSize = .zero

    // MARK: - 顶点数据

    struct Vertex {
        var position: SIMD4<Float>
        var texCoord: SIMD2<Float>
    }

    // MARK: - 初始化

    init?(device: MTLDevice? = nil) {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            return nil
        }

        self.device = device

        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = queue

        super.init()

        setupPipeline()
        setupSampler()
    }

    // MARK: - 设置

    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            createDefaultPipeline()
            return
        }

        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
            createDefaultPipeline()
        }
    }

    private func createDefaultPipeline() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float4 position [[attribute(0)]];
            float2 texCoord [[attribute(1)]];
        };

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                                      constant float4 *positions [[buffer(0)]],
                                      constant float2 *texCoords [[buffer(1)]]) {
            VertexOut out;
            out.position = positions[vertexID];
            out.texCoord = texCoords[vertexID];
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<float> texture [[texture(0)]],
                                       sampler textureSampler [[sampler(0)]]) {
            return texture.sample(textureSampler, in.texCoord);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create default pipeline: \(error)")
        }
    }

    private func setupSampler() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    // MARK: - 纹理管理

    private func createTexture(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        guard width != textureWidth || height != textureHeight else { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        texture = device.makeTexture(descriptor: descriptor)
        textureWidth = width
        textureHeight = height

        updateVertexBuffer()
    }

    private func updateVertexBuffer() {
        guard textureWidth > 0, textureHeight > 0, viewSize.width > 0, viewSize.height > 0 else { return }

        let (positions, texCoords) = calculateVertexData()

        let positionData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let texCoordData = texCoords.withUnsafeBufferPointer { Data(buffer: $0) }

        let vertexData = positionData + texCoordData
        vertexBuffer = device.makeBuffer(bytes: [UInt8](vertexData),
                                         length: vertexData.count,
                                         options: .storageModeShared)
    }

    private func calculateVertexData() -> ([SIMD4<Float>], [SIMD2<Float>]) {
        let textureAspect = Float(textureWidth) / Float(textureHeight)
        let viewAspect = Float(viewSize.width) / Float(viewSize.height)

        var scaleX: Float = 1.0
        var scaleY: Float = 1.0

        switch scaleMode {
        case .fit:
            if textureAspect > viewAspect {
                scaleY = viewAspect / textureAspect
            } else {
                scaleX = textureAspect / viewAspect
            }
        case .fill:
            if textureAspect > viewAspect {
                scaleX = textureAspect / viewAspect
            } else {
                scaleY = viewAspect / textureAspect
            }
        case .native:
            scaleX = Float(textureWidth) / Float(viewSize.width)
            scaleY = Float(textureHeight) / Float(viewSize.height)
        }

        let positions: [SIMD4<Float>] = [
            SIMD4(-scaleX, -scaleY, 0, 1),  // 左下
            SIMD4( scaleX, -scaleY, 0, 1),  // 右下
            SIMD4(-scaleX,  scaleY, 0, 1),  // 左上
            SIMD4( scaleX,  scaleY, 0, 1),  // 右上
        ]

        let texCoords: [SIMD2<Float>] = [
            SIMD2(0, 1),  // 左下
            SIMD2(1, 1),  // 右下
            SIMD2(0, 0),  // 左上
            SIMD2(1, 0),  // 右上
        ]

        return (positions, texCoords)
    }

    // MARK: - 渲染

    func updateTexture() {
        guard let frameBuffer = frameBuffer, let texture = texture else { return }

        if frameBuffer.hasDirtyRegions {
            let dirtyRegions = frameBuffer.popDirtyRegions()
            for region in dirtyRegions {
                frameBuffer.copyRegionToTexture(texture, region: region)
            }
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewSize = size
        updateVertexBuffer()
    }

    func draw(in view: MTKView) {
        updateTexture()

        guard let pipelineState = pipelineState,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)

        if let texture = texture {
            renderEncoder.setFragmentTexture(texture, index: 0)
        }

        if let samplerState = samplerState {
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        }

        if let vertexBuffer = vertexBuffer {
            let positionOffset = 0
            let texCoordOffset = MemoryLayout<SIMD4<Float>>.stride * 4

            renderEncoder.setVertexBuffer(vertexBuffer, offset: positionOffset, index: 0)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: texCoordOffset, index: 1)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - 坐标转换

    /// 将视图坐标转换为纹理坐标
    func viewToTextureCoordinate(_ point: CGPoint, viewSize: CGSize) -> CGPoint? {
        guard textureWidth > 0, textureHeight > 0 else { return nil }

        let textureAspect = CGFloat(textureWidth) / CGFloat(textureHeight)
        let viewAspect = viewSize.width / viewSize.height

        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        switch scaleMode {
        case .fit:
            if textureAspect > viewAspect {
                let scaledHeight = viewSize.width / textureAspect
                scaleY = viewSize.height / scaledHeight
                offsetY = (viewSize.height - scaledHeight) / 2
            } else {
                let scaledWidth = viewSize.height * textureAspect
                scaleX = viewSize.width / scaledWidth
                offsetX = (viewSize.width - scaledWidth) / 2
            }
        case .fill, .native:
            break
        }

        let normalizedX = (point.x - offsetX) / (viewSize.width - 2 * offsetX)
        let normalizedY = (point.y - offsetY) / (viewSize.height - 2 * offsetY)

        guard normalizedX >= 0, normalizedX <= 1, normalizedY >= 0, normalizedY <= 1 else {
            return nil
        }

        return CGPoint(x: normalizedX * CGFloat(textureWidth),
                       y: normalizedY * CGFloat(textureHeight))
    }
}
