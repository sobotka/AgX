// OBS-specific syntax adaptation to HLSL standard to avoid errors reported by the code editor
#define SamplerState sampler_state
#define Texture2D texture2d

// Uniform variables set by OBS (required)
uniform float4x4 ViewProj; // View-projection matrix used in the vertex shader
uniform Texture2D image;   // Texture containing the source picture

uniform int INPUT_COLORSPACE = 0;
uniform float INPUT_EXPOSURE = 0.75;
uniform float INPUT_GAMMA = 1.0;
uniform float INPUT_SATURATION = 1.0;
uniform float INPUT_HIGHLIGHT_GAIN = 0.0;
uniform float INPUT_HIGHLIGHT_GAIN_GAMMA = 1.0;
uniform float PUNCH_EXPOSURE = 0.0;
uniform float PUNCH_SATURATION = 1.0;
uniform float PUNCH_GAMMA = 1.3;
uniform bool USE_OCIO_LOG = false;
uniform bool APPLY_OUTSET = true;
uniform float3 luma_coefs_bt709 = {0.2126, 0.7152, 0.0722};

/*=================
    OBS BOILERPLATE
=================*/

// Interpolation method and wrap mode for sampling a texture
SamplerState linear_clamp
{
    Filter    = Linear;     // Anisotropy / Point / Linear
    AddressU  = Clamp;      // Wrap / Clamp / Mirror / Border / MirrorOnce
    AddressV  = Clamp;      // Wrap / Clamp / Mirror / Border / MirrorOnce
    BorderColor = 00000000; // Used only with Border edges (optional)
};
struct VertexData
{
    float4 pos : POSITION;  // Homogeneous space coordinates XYZW
    float2 uv  : TEXCOORD0; // UV coordinates in the source picture
};
struct PixelData
{
    float4 pos : POSITION;  // Homogeneous screen coordinates XYZW
    float2 uv  : TEXCOORD0; // UV coordinates in the source picture
};


/*=================
    API
=================*/


float getLuminance(float3 image)
// Return approximative perceptive luminance of the image.
{
    return dot(image, luma_coefs_bt709);
}

float3 powsafe(float3 color, float power)
// pow() but safe for NaNs/negatives
{
    return pow(abs(color), power) * sign(color);
}

float3 saturation(float3 color, float saturationAmount)
/*

    Increase color saturation of the given color data.

    :param color: expected sRGB primaries input
    :oaram saturationAmount: expected 0-1 range with 1=neutral, 0=no saturation.

    -- ref[2] [4]
*/
{
    float luma = getLuminance(color);
    return lerp(luma, color, saturationAmount);
}

float3 cctf_decoding_pow2_2(float3 color){return powsafe(color, 2.2);}

float3 cctf_encoding_pow2_2(float3 color){return powsafe(color, 1/2.2);}

/*=================
    Main processes
=================*/


float3 applyInputTransform(float3 Image)
/*
    Convert input to workspace colorspace an apply pre-grading.
*/
{

    if (INPUT_COLORSPACE == 0){Image = cctf_decoding_pow2_2(Image);}

    float ImageLuma = powsafe(getLuminance(Image), INPUT_HIGHLIGHT_GAIN_GAMMA);
    Image += Image * ImageLuma.xxx * INPUT_HIGHLIGHT_GAIN;

    Image = saturation(Image, INPUT_SATURATION);
    Image = powsafe(Image, INPUT_GAMMA);
    Image *= powsafe(2.0, INPUT_EXPOSURE);
    return Image;
}


PixelData VERTEXSHADER_AgX(VertexData vertex)
{
    PixelData pixel;
    pixel.pos = mul(float4(vertex.pos.xyz, 1.0), ViewProj);
    pixel.uv  = vertex.uv;
    return pixel;
}

float4 PIXELSHADER_AgX(PixelData pixel) : TARGET
{
    float4 OriginalImage = image.Sample(linear_clamp, pixel.uv);
    float3 Image = applyInputTransform(OriginalImage.rgb);
    Image = cctf_encoding_pow2_2(Image);
    return float4(Image.rgb, OriginalImage.a);
}


technique Draw
{
    pass
    {
        vertex_shader = VERTEXSHADER_AgX(vertex);
        pixel_shader  = PIXELSHADER_AgX(pixel);
    }
}