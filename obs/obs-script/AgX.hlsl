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
#include "colorspace.hlsl"

// OBS-specific syntax adaptation to HLSL standard to avoid errors reported by the code editor
#define SamplerState sampler_state
#define Texture2D texture2d

// Uniform variables set by OBS (required)
uniform float4x4 ViewProj; // View-projection matrix used in the vertex shader
uniform Texture2D image;   // Texture containing the source picture

uniform int INPUT_COLORSPACE = 1;
/*
uniform int colorspaceid_Passthrough = 0;
uniform int colorspaceid_sRGB_Display_EOTF = 1;
uniform int colorspaceid_sRGB_Display_2_2 = 2;
uniform int colorspaceid_sRGB_Linear = 3;
uniform int colorspaceid_BT_709_Display_2_4 = 4;
uniform int colorspaceid_DCIP3_Display_2_6 = 5;
uniform int colorspaceid_Apple_Display_P3 = 6;
*/
uniform float INPUT_EXPOSURE = 0.75;
uniform float INPUT_GAMMA = 1.0;
uniform float INPUT_SATURATION = 1.0;
uniform float INPUT_HIGHLIGHT_GAIN = 0.0;
uniform float INPUT_HIGHLIGHT_GAIN_GAMMA = 1.0;
uniform float PUNCH_EXPOSURE = 0.0;
uniform float PUNCH_SATURATION = 1.0;
uniform float PUNCH_GAMMA = 1.3;
uniform int OUTPUT_COLORSPACE = 1;  // same as INPUT_COLORSPACE
uniform bool USE_OCIO_LOG = false;
uniform bool APPLY_OUTSET = true;

// LUT AgX-default_contrast.lut.png
uniform texture2d AgXLUT;
#define AgXLUT_BLOCK_SIZE 32
#define AgXLUT_DIMENSIONS int2(AgXLUT_BLOCK_SIZE * AgXLUT_BLOCK_SIZE, AgXLUT_BLOCK_SIZE)
#define AgXLUT_PIXEL_SIZE 1.0 / AgXLUT_DIMENSIONS

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
    Main processes
=================*/


float3 applyInputTransform(float3 Image)
/*
    Convert input to workspace colorspace (sRGB)
*/
{
    return convertColorspaceToColorspace(Image, INPUT_COLORSPACE, colorspaceid_sRGB_Linear);
}

float3 applyGrading(float3 Image)
/*
    Apply creative grading operations (pre-display-transform).
*/
{

    float ImageLuma = powsafe(get_luminance(Image), INPUT_HIGHLIGHT_GAIN_GAMMA);
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

    float3x3 agx_compressed_matrix = {
        0.84247906, 0.0784336, 0.07922375,
        0.04232824, 0.87846864, 0.07916613,
        0.04237565, 0.0784336, 0.87914297
    };

    Image = max(0.0, Image); // clamp negatives
    // why this doesn't work ??
    // Image = mul(agx_compressed_matrix, Image);
	Image = apply_matrix(Image, agx_compressed_matrix);

    if (USE_OCIO_LOG)
        Image = cctf_log2_ocio_transform(Image);
    else
        Image = cctf_log2_normalized_from_open_domain(Image, -10.0, 6.5);

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
    Image = cctf_decoding_Power_2_2(Image);
    return Image;
}

float3 applyOutset(float3 Image)
/*
    Outset is the inverse of the inset applied during `applyAgXLog`
    and restore chroma.
*/
{

    float3x3 agx_compressed_matrix_inverse = {
        1.1968790, -0.09802088, -0.09902975,
        -0.05289685, 1.15190313, -0.09896118,
        -0.05297163, -0.09804345, 1.15107368
    };
	Image = apply_matrix(Image, agx_compressed_matrix_inverse);

    return Image;
}

float3 applyODT(float3 Image)
/*
    Apply Agx to display conversion.

    :param color: linear - sRGB data.

*/
{
    if (OUTPUT_COLORSPACE == 1) Image = cctf_encoding_sRGB_EOTF(Image);
    if (OUTPUT_COLORSPACE == 2) Image = cctf_encoding_Power_2_2(Image);
    if (OUTPUT_COLORSPACE == 3) Image = cctf_encoding_BT_709(Image);
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

    Image = convertColorspaceToColorspace(Image, 1, 4);

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