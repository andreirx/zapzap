#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

typedef struct {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
} Vertex;

typedef struct {
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

typedef struct {
    float4x4 projectionMatrix;
} UniformScene;

typedef struct {
    float4x4 modelMatrix;
} UniformModel;

vertex ColorInOut vertex_main(Vertex in [[stage_in]],
                              constant UniformScene &uniformScene [[buffer(2)]],
                              constant UniformModel &uniformModel [[buffer(3)]]) {
    ColorInOut out;
    float4 position = float4(in.position, 1.0);
    out.position = uniformScene.projectionMatrix * uniformModel.modelMatrix * position;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 sprite_fragment_main(ColorInOut in [[stage_in]],
                                     texture2d<float> colorTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mip_filter::linear,
                                     mag_filter::linear,
                                     min_filter::linear);
    float4 color = colorTexture.sample(textureSampler, in.texCoord);
    return color;
}

fragment float4 additive_fragment_main(ColorInOut in [[stage_in]],
                                       texture2d<float> colorTexture [[texture(0)]]) {
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    float4 color = colorTexture.sample(textureSampler, in.texCoord);
    return color * 6.4; // increase brightness for additive blending
}
