/*
HLSL implementation of AgX (by Troy Sobotka) for OBS.

author = "Liam Collod"
repository = "https://github.com/MrLixm/AgXc"

References:
- [0] https://github.com/sobotka/AgX-S2O3/blob/main/AgX.py
- [1] https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.postprocessing/PostProcessing/Shaders/Colors.hlsl
- [2] https://video.stackexchange.com/q/9866
- [3] https://github.com/Fubaxiusz/fubax-shaders/blob/master/Shaders/LUTTools.fx
- [4] https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.postprocessing/PostProcessing/Shaders/Colors.hlsl#L574
- [5] https://github.com/colour-science/colour/blob/develop/colour/models/rgb/transfer_functions/srgb.py#L99
*/

// OBS-specific syntax adaptation to HLSL standard to avoid errors reported by the code editor
#define SamplerState sampler_state
#define Texture2D texture2d

// Uniform variables set by OBS (required)
uniform float4x4 ViewProj; // View-projection matrix used in the vertex shader
uniform Texture2D image;   // Texture containing the source picture

uniform int INPUT_COLORSPACE = 1;
/*
0 = Passthrough,
1 = sRGB Display (EOTF),
2 = sRGB Display (2.2),
*/
uniform float INPUT_EXPOSURE = 0.75;
uniform float INPUT_GAMMA = 1.0;
uniform float INPUT_SATURATION = 1.0;
uniform float INPUT_HIGHLIGHT_GAIN = 0.0;
uniform float INPUT_HIGHLIGHT_GAIN_GAMMA = 1.0;
uniform float PUNCH_EXPOSURE = 0.0;
uniform float PUNCH_SATURATION = 1.0;
uniform float PUNCH_GAMMA = 1.3;
uniform int OUTPUT_COLORSPACE = 1;
/*
0 = Passthrough,
1 = sRGB Display (EOTF),
2 = sRGB Display (2.2),
*/
uniform bool USE_OCIO_LOG = false;
uniform bool APPLY_OUTSET = true;

// LUT AgX-default_contrast.lut.png
uniform texture2d AgXLUT;
#define AgXLUT_BLOCK_SIZE 32
#define AgXLUT_DIMENSIONS int2(AgXLUT_BLOCK_SIZE * AgXLUT_BLOCK_SIZE, AgXLUT_BLOCK_SIZE)
#define AgXLUT_PIXEL_SIZE 1.0 / AgXLUT_DIMENSIONS

uniform float3 luma_coefs_bt709 = {0.2126, 0.7152, 0.0722};
// TODO not used for now cause doesn't work that way
uniform float3x3 agx_compressed_matrix = {
    0.84247906, 0.0784336, 0.07922375,
    0.04232824, 0.87846864, 0.07916613,
    0.04237565, 0.0784336, 0.87914297
};
uniform float3x3 agx_compressed_matrix_inverse = {
    1.1968790, -0.09802088, -0.09902975,
    -0.05289685, 1.15190313, -0.09896118,
    -0.05297163, -0.09804345, 1.15107368
};

/*=================
    OBS BOILERPLATE
=================*/

// Interpolation method and wrap mode for sampling a texture
sampler_state linear_clamp
{
    Filter    = Linear;     // Anisotropy / Point / Linear
    AddressU  = Clamp;      // Wrap / Clamp / Mirror / Border / MirrorOnce
    AddressV  = Clamp;      // Wrap / Clamp / Mirror / Border / MirrorOnce
    BorderColor = 00000000; // Used only with Border edges (optional)
};
sampler_state LUTSampler
{
	Filter    = Linear;
	AddressU  = Clamp;
	AddressV  = Clamp;
	AddressW  = Clamp;
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

float3 cctf_decoding_sRGB(float3 color)
// ref[5]
{
    return (color <= 0.04045) ? (color / 12.92) : (powsafe((color + 0.055) / 1.055, 2.4));
}

float3 cctf_encoding_sRGB(float3 color)
// ref[5]
{
    return (color <= 0.0031308) ? (color * 12.92) : (1.055 * powsafe(color, 1/2.4) - 0.055);
}

float3 cctf_decoding_pow2_2(float3 color){return powsafe(color, 2.2);}

float3 cctf_encoding_pow2_2(float3 color){return powsafe(color, 1/2.2);}


float3 convertOpenDomainToNormalizedLog2(float3 color, float minimum_ev, float maximum_ev)
/*
    Output log domain encoded data.

    Similar to OCIO lg2 AllocationTransform.

    ref[0]
*/
{
    float in_midgrey = 0.18;

    // remove negative before log transform
    color = max(0.0, color);
    // avoid infinite issue with log -- ref[1]
    color = (color  < 0.00003051757) ? (0.00001525878 + color) : (color);
    color = clamp(
        log2(color / in_midgrey),
        float3(minimum_ev, minimum_ev, minimum_ev),
        float3(maximum_ev,maximum_ev,maximum_ev)
    );
    float total_exposure = maximum_ev - minimum_ev;

    return (color - minimum_ev) / total_exposure;
}

// exactly the same as above but I let it for reference
float3 log2Transform(float3 color)
/*
    Output log domain encoded data.

    Copy of OCIO lg2 AllocationTransform with the AgX Log values.

    :param color: rgba linear color data
*/
{
    // remove negative before log transform
    color = max(0.0, color);
    color = (color  < 0.00003051757) ? (log2(0.00001525878 + color * 0.5)) : (log2(color));

    // obtained via m = ocio.MatrixTransform.Fit(oldMin=[-12.47393, -12.47393, -12.47393, 0.0], oldMax=[4.026069, 4.026069, 4.026069, 1.0])
    float3x3 fitMatrix = float3x3(
        0.060606064279155415, 0.0, 0.0,
        0.0, 0.060606064279155415, 0.0,
        0.0, 0.0, 0.060606064279155415
    );
    // obtained via same as above
    float fitMatrixOffset = 0.7559958033936851;
    color = mul(fitMatrix, color);
    color += fitMatrixOffset.xxx;

    return color;
}

/*=================
    Main processes
=================*/


float3 applyInputTransform(float3 Image)
/*
    Convert input to workspace colorspace.
*/
{
    if (INPUT_COLORSPACE == 1) Image = cctf_decoding_sRGB(Image);
    if (INPUT_COLORSPACE == 2) Image = cctf_decoding_pow2_2(Image);
    return Image;
}

float3 applyGrading(float3 Image)
/*
    Apply creative grading operations (pre-display-transform).
*/
{

    float ImageLuma = powsafe(getLuminance(Image), INPUT_HIGHLIGHT_GAIN_GAMMA);
    Image += Image * ImageLuma.xxx * INPUT_HIGHLIGHT_GAIN;

    Image = saturation(Image, INPUT_SATURATION);
    Image = powsafe(Image, INPUT_GAMMA);
    Image *= powsafe(2.0, INPUT_EXPOSURE);
    return Image;
}

float3 applyAgXLog(float3 Image)
/*
    Prepare the data for display encoding. Converted to log domain.
*/
{
    Image = max(0.0, Image); // clamp negatives
    // why this doesn't work ??
    // Image = mul(agx_compressed_matrix, Image);
	float r = dot(Image, float3(0.84247906, 0.0784336, 0.07922375));
	float g = dot(Image, float3(0.04232824, 0.87846864, 0.07916613));
	float b = dot(Image, float3(0.04237565, 0.0784336, 0.87914297));
	Image = float3(r, g, b);

    if (USE_OCIO_LOG)
        Image = log2Transform(Image);
    else
        Image = convertOpenDomainToNormalizedLog2(Image, -10.0, 6.5);

    Image = clamp(Image, 0.0, 1.0);
    return Image;
}

float3 applyAgXLUT(float3 Image)
/*
    Apply the AgX 1D curve on log encoded data.

    The output is similar to AgX Base which is considered
    sRGB - Display, but here we linearize it.

    -- ref[3] for LUT implementation
*/
{

    float3 lut3D = Image * (AgXLUT_BLOCK_SIZE-1);

    float2 lut2D[2];
    // Front
    lut2D[0].x = floor(lut3D.z) * AgXLUT_BLOCK_SIZE+lut3D.x;
    lut2D[0].y = lut3D.y;
    // Back
    lut2D[1].x = ceil(lut3D.z) * AgXLUT_BLOCK_SIZE+lut3D.x;
    lut2D[1].y = lut3D.y;

    // Convert from texel to texture coords
    lut2D[0] = (lut2D[0]+0.5) * AgXLUT_PIXEL_SIZE;
    lut2D[1] = (lut2D[1]+0.5) * AgXLUT_PIXEL_SIZE;

    // Bicubic LUT interpolation
    Image = lerp(
        AgXLUT.Sample(LUTSampler, lut2D[0]).rgb, // Front Z
        AgXLUT.Sample(LUTSampler, lut2D[1]).rgb, // Back Z
        frac(lut3D.z)
    );
    // LUT apply the transfer function so we remove it to keep working on linear data.
    Image = cctf_decoding_pow2_2(Image);
    return Image;
}

float3 applyOutset(float3 Image)
/*
    Outset is the inverse of the inset applied during `applyAgXLog`
    and restore chroma.
*/
{
    // Image = mul(agx_compressed_matrix_inverse, Image);
    float r = dot(Image, float3(1.1968790, -0.09802088, -0.09902975));
	float g = dot(Image, float3(-0.05289685, 1.15190313, -0.09896118));
	float b = dot(Image, float3(-0.05297163, -0.09804345, 1.15107368));
	Image = float3(r, g, b);

    return Image;
}

float3 applyODT(float3 Image)
/*
    Apply Agx to display conversion.

    :param color: linear - sRGB data.

*/
{
    if (OUTPUT_COLORSPACE == 1) Image = cctf_encoding_sRGB(Image);
    if (OUTPUT_COLORSPACE == 2) Image = cctf_encoding_pow2_2(Image);
    return Image;
}


float3 applyLookPunchy(float3 Image)
/*
    Applies the post "Punchy" look to display-encoded data.

    Input is expected to be in a display-state.
*/
{
    Image = powsafe(Image, PUNCH_GAMMA);
    Image = saturation(Image, PUNCH_SATURATION);
    Image *= powsafe(2.0, PUNCH_EXPOSURE);  // not part of initial cdl
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
    float3 Image = OriginalImage.rgb;
    Image = applyInputTransform(Image);
    Image = applyGrading(Image);
    Image = applyAgXLog(Image);
    Image = applyAgXLUT(Image);
    if (APPLY_OUTSET)
        Image = applyOutset(Image);
    Image = applyODT(Image);
    Image = applyLookPunchy(Image);
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