#include <metal_stdlib>
using namespace metal;

// 顶点输入结构
struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// 顶点输出/片段输入结构
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 顶点着色器
vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant float4 *positions [[buffer(0)]],
                              constant float2 *texCoords [[buffer(1)]]) {
    VertexOut out;
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

// 基础片段着色器
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]],
                               sampler textureSampler [[sampler(0)]]) {
    float4 color = texture.sample(textureSampler, in.texCoord);
    return color;
}

// 带亮度/对比度调整的片段着色器
fragment float4 fragmentShaderAdjusted(VertexOut in [[stage_in]],
                                       texture2d<float> texture [[texture(0)]],
                                       sampler textureSampler [[sampler(0)]],
                                       constant float &brightness [[buffer(0)]],
                                       constant float &contrast [[buffer(1)]]) {
    float4 color = texture.sample(textureSampler, in.texCoord);

    // 亮度调整
    color.rgb += brightness;

    // 对比度调整
    color.rgb = (color.rgb - 0.5) * contrast + 0.5;

    // 限制范围
    color.rgb = clamp(color.rgb, 0.0, 1.0);

    return color;
}

// YUV 转 RGB 片段着色器 (用于视频解码)
fragment float4 fragmentShaderYUV(VertexOut in [[stage_in]],
                                  texture2d<float> textureY [[texture(0)]],
                                  texture2d<float> textureUV [[texture(1)]],
                                  sampler textureSampler [[sampler(0)]]) {
    // BT.709 YUV 转 RGB 矩阵
    const float3x3 colorMatrix = float3x3(
        float3(1.0,  1.0,     1.0),
        float3(0.0, -0.18732, 1.8556),
        float3(1.5748, -0.46812, 0.0)
    );

    float y = textureY.sample(textureSampler, in.texCoord).r;
    float2 uv = textureUV.sample(textureSampler, in.texCoord).rg - float2(0.5, 0.5);

    float3 yuv = float3(y, uv.x, uv.y);
    float3 rgb = colorMatrix * yuv;

    return float4(clamp(rgb, 0.0, 1.0), 1.0);
}

// 光标叠加片段着色器
fragment float4 fragmentShaderWithCursor(VertexOut in [[stage_in]],
                                         texture2d<float> desktopTexture [[texture(0)]],
                                         texture2d<float> cursorTexture [[texture(1)]],
                                         sampler textureSampler [[sampler(0)]],
                                         constant float2 &cursorPos [[buffer(0)]],
                                         constant float2 &cursorSize [[buffer(1)]],
                                         constant float2 &textureSize [[buffer(2)]]) {
    float4 desktopColor = desktopTexture.sample(textureSampler, in.texCoord);

    // 计算当前像素在纹理中的位置
    float2 pixelPos = in.texCoord * textureSize;

    // 检查是否在光标区域内
    float2 cursorStart = cursorPos;
    float2 cursorEnd = cursorPos + cursorSize;

    if (pixelPos.x >= cursorStart.x && pixelPos.x < cursorEnd.x &&
        pixelPos.y >= cursorStart.y && pixelPos.y < cursorEnd.y) {
        // 计算光标纹理坐标
        float2 cursorTexCoord = (pixelPos - cursorStart) / cursorSize;
        float4 cursorColor = cursorTexture.sample(textureSampler, cursorTexCoord);

        // Alpha 混合
        desktopColor.rgb = mix(desktopColor.rgb, cursorColor.rgb, cursorColor.a);
    }

    return desktopColor;
}

// 带边缘平滑的放大片段着色器
fragment float4 fragmentShaderBicubic(VertexOut in [[stage_in]],
                                      texture2d<float> texture [[texture(0)]],
                                      constant float2 &textureSize [[buffer(0)]]) {
    float2 texCoord = in.texCoord * textureSize - 0.5;
    float2 fxy = fract(texCoord);
    texCoord -= fxy;

    // Mitchell-Netravali 三次插值参数
    const float B = 1.0/3.0;
    const float C = 1.0/3.0;

    auto mitchell = [B, C](float x) -> float {
        x = abs(x);
        if (x < 1.0) {
            return ((12.0 - 9.0*B - 6.0*C) * x*x*x +
                   (-18.0 + 12.0*B + 6.0*C) * x*x +
                   (6.0 - 2.0*B)) / 6.0;
        } else if (x < 2.0) {
            return ((-B - 6.0*C) * x*x*x +
                   (6.0*B + 30.0*C) * x*x +
                   (-12.0*B - 48.0*C) * x +
                   (8.0*B + 24.0*C)) / 6.0;
        }
        return 0.0;
    };

    float4 result = float4(0.0);
    float weightSum = 0.0;

    for (int y = -1; y <= 2; y++) {
        for (int x = -1; x <= 2; x++) {
            float2 sampleCoord = (texCoord + float2(x, y) + 0.5) / textureSize;
            float weight = mitchell(float(x) - fxy.x) * mitchell(float(y) - fxy.y);
            result += texture.sample(sampler(filter::nearest), sampleCoord) * weight;
            weightSum += weight;
        }
    }

    return result / weightSum;
}
