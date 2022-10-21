/*
HLSL implementation of AgX by Troy Sobotka.

Converted from python implementation: https://gist.github.com/MrLixm/946c1b59cce8b74e948e75618583ce8d

References:
- [0] https://github.com/sobotka/AgX-S2O3/blob/main/AgX.py
- [1] https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.postprocessing/PostProcessing/Shaders/Colors.hlsl
- [2] https://video.stackexchange.com/q/9866
- [3] https://github.com/Fubaxiusz/fubax-shaders/blob/master/Shaders/LUTTools.fx
*/

// Define LUT texture size
#ifndef LUT_BLOCK_SIZE
	#define LUT_BLOCK_SIZE 32
#endif

#define LUT_DIMENSIONS int2(LUT_BLOCK_SIZE*LUT_BLOCK_SIZE, LUT_BLOCK_SIZE)
#define LUT_PIXEL_SIZE 1.0/LUT_DIMENSIONS

uniform bool INPUT_LINEARIZE <
    ui_label = "Linearize Input (sRGB)";
    ui_tooltip = "Apply the CCTF decoding for sRGB colorspace.";
    ui_category = "Input";
> = true;

uniform float INPUT_HDR_GAIN <
	ui_type = "drag";
	ui_min = 1.0;
    ui_max = 10.0;
    ui_step = 0.01;
    ui_label = "HDR Gain";
    ui_tooltip = "Increase dynamic range by boosting highlight (fake).";
    ui_category = "Input";
> = 1.0;

uniform float PUNCH_SATURATION <
	ui_type = "drag";
	ui_min = 0.5;
    ui_max = 3;
    ui_step = 0.01;
    ui_label = "Punchy Saturation";
    ui_tooltip = "Post display conversion.";
    ui_category = "Output";
> = 1.2;

uniform float PUNCH_GAMMA <
	ui_type = "drag";
	ui_min = 0.5;
    ui_max = 2;
    ui_step = 0.01;
    ui_label = "Punchy Gamma";
    ui_tooltip = "Post display conversion.";
    ui_category = "Output";
> = 1.3;

texture LUTTex < source = "AgX-default_contrast.lut.png"; > { Width = LUT_DIMENSIONS.x; Height = LUT_DIMENSIONS.y; Format = RGBA8; };
sampler LUTSampler {Texture = LUTTex; Format = RGBA8;};


static const float3 luma_coefs_bt709 = (0.2126, 0.7152, 0.0722);
static const float3x3 agx_compressed_matrix = float3x3(
    0.84247906, 0.0784336, 0.07922375,
    0.04232824, 0.87846864, 0.07916613,
    0.04237565, 0.0784336, 0.87914297
);


#include "ReShade.fxh"



float3 powsafe(float3 color, float power)
// pow() but safe for NaNs/negatives
{
    return pow(abs(color), power) * sign(color);
}

float3 saturation(float3 color, float saturation)
// except sRGB primaries input
// ref[2]
{
    float3 luma = dot(luma_coefs_bt709, color);
    return luma + saturation * (color - luma);
}


float3 cctf_decoding_sRGB(float3 color)
// :param color: sRGB EOTF encoded
{
    return powsafe(color, 2.2);
}

float3 cctf_encoding_sRGB(float3 color)
// :param color: linear transfer-function encoded
{
    return powsafe(color, 1/2.2);
}


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

    color = clamp(
        // avoid infinite issue with log ref[1]
        log2(((color  < 0.00003051757) ? (0.00001525878 + color) : (color)) / in_midgrey),
        float3(minimum_ev, minimum_ev, minimum_ev),
        float3(maximum_ev,maximum_ev,maximum_ev)
    );
    float total_exposure = maximum_ev - minimum_ev;

    return (color - minimum_ev) / total_exposure;
}


void PS_IDT(float4 vpos : SV_Position, float2 TexCoord : TEXCOORD, out float3 Image : SV_Target)
/*
    Convert input to workspace colorspace.
*/
{
    Image = tex2D(ReShade::BackBuffer, TexCoord).rgb;

    if (INPUT_LINEARIZE) Image = cctf_decoding_sRGB(Image);

    Image += Image * INPUT_HDR_GAIN;
    Image *= 0.3;

}

void PS_PreAgX(float4 vpos : SV_Position, float2 TexCoord : TEXCOORD, out float3 Image : SV_Target)
/*
    Prepare the data for display encoding. Converted to log domain.
*/
{
    Image = tex2D(ReShade::BackBuffer, TexCoord).rgb;

    Image = max(0.0, Image); // clamp negatives
    Image = mul(agx_compressed_matrix, Image);
    Image = convertOpenDomainToNormalizedLog2(Image, -10.0, 6.5);
    Image = clamp(Image, 0.0, 1.0);
}


void PS_AgXLUT(float4 vpos : SV_Position, float2 TexCoord : TEXCOORD, out float3 Image : SV_Target)
/*
    Apply the AgX 1D curve on log encoded data.

    ref[3]
*/
{

    Image = tex2D(ReShade::BackBuffer, TexCoord).rgb;

	float3 lut3D = Image*(LUT_BLOCK_SIZE-1);

    float2 lut2D[2];
	// Front
    lut2D[0].x = floor(lut3D.z)*LUT_BLOCK_SIZE+lut3D.x;
    lut2D[0].y = lut3D.y;
    // Back
    lut2D[1].x = ceil(lut3D.z)*LUT_BLOCK_SIZE+lut3D.x;
    lut2D[1].y = lut3D.y;

	// Convert from texel to texture coords
	lut2D[0] = (lut2D[0]+0.5)*LUT_PIXEL_SIZE;
	lut2D[1] = (lut2D[1]+0.5)*LUT_PIXEL_SIZE;

	// Bicubic LUT interpolation
	Image = lerp(
		tex2D(LUTSampler, lut2D[0]).rgb, // Front Z
		tex2D(LUTSampler, lut2D[1]).rgb, // Back Z
		frac(lut3D.z)
	);
}


void PS_LookPunchy(float4 vpos : SV_Position, float2 TexCoord : TEXCOORD, out float3 Image : SV_Target)
/*
    Applies the post "Punchy" look to display-encoded data.

    Initally an OCIO CDLTransform.
    SRC: /src/OpenColorIO/ops/cdl/CDLOpCPU.cpp#L348
    "default style is CDL_NO_CLAMP"
*/
{
    Image = tex2D(ReShade::BackBuffer, TexCoord).rgb;

    Image = powsafe(Image, PUNCH_GAMMA);
    Image = saturation(Image, PUNCH_SATURATION);
}


technique AgX_processing
{
    pass IDT
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_IDT;
    }
    pass PreAgX
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_PreAgX;
	}
    pass AgXLUT
    {
		VertexShader = PostProcessVS;
		PixelShader = PS_AgXLUT;
    }
    pass PS_LookPunchy
    {
		VertexShader = PostProcessVS;
		PixelShader = PS_LookPunchy;
    }
}
