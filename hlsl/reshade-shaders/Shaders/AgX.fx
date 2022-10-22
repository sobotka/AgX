/*
HLSL implementation of AgX by Troy Sobotka.

Converted from python implementation: https://gist.github.com/MrLixm/946c1b59cce8b74e948e75618583ce8d

References:
- [0] https://github.com/sobotka/AgX-S2O3/blob/main/AgX.py
- [1] https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.postprocessing/PostProcessing/Shaders/Colors.hlsl
- [2] https://video.stackexchange.com/q/9866
- [3] https://github.com/Fubaxiusz/fubax-shaders/blob/master/Shaders/LUTTools.fx
- [4] https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.postprocessing/PostProcessing/Shaders/Colors.hlsl#L574
- [5] https://github.com/colour-science/colour/blob/develop/colour/models/rgb/transfer_functions/srgb.py#L99
*/

#include "ReShade.fxh"

// Define LUT texture size
#ifndef LUT_BLOCK_SIZE
	#define LUT_BLOCK_SIZE 32
#endif

#define LUT_DIMENSIONS int2(LUT_BLOCK_SIZE*LUT_BLOCK_SIZE, LUT_BLOCK_SIZE)
#define LUT_PIXEL_SIZE 1.0/LUT_DIMENSIONS

uniform int INPUT_COLORSPACE <
    ui_type = "combo";
    ui_label = "Source Colorspace";
    ui_items= "sRGB Display (EOTF)\0sRGB Display (2.2)\0Passthrough\0";
    ui_tooltip = "In which colorspace is encoded the input.";
    ui_category = "Input";
> = 0;

uniform float INPUT_EXPOSURE <
	ui_type = "drag";
	ui_min = -5;
    ui_max = 5.0;
    ui_step = 0.01;
    ui_label = "Exposure";
    ui_tooltip = "Change overall image exposure. 0.0 means neutral.Applied last.\nBoosted by default to compensate for low-dynamic range of the input.";
    ui_category = "Input";
> = 0.75;

uniform float INPUT_GAMMA <
	ui_type = "drag";
	ui_min = 0.001;
    ui_max = 5.0;
    ui_step = 0.01;
    ui_label = "Gamma";
    ui_tooltip = "Change overall image gamma. 1.0 means neutral. Applied before Exposure.";
    ui_category = "Input";
> = 1.0;

uniform float INPUT_SATURATION <
	ui_type = "drag";
	ui_min = 0.0;
    ui_max = 5.0;
    ui_step = 0.01;
    ui_label = "Saturation";
    ui_tooltip = "Boost saturation before AgX transforms. Applied first.";
    ui_category = "Input";
> = 1.0;

uniform float INPUT_HIGHLIGHT_GAIN <
	ui_type = "drag";
	ui_min = 0.0;
    ui_max = 5.0;
    ui_step = 0.01;
    ui_label = "Highlight Gain";
    ui_tooltip = "Increase dynamic range (in a fake way) by boosting highlights.";
    ui_category = "Input";
> = 0.0;

uniform float INPUT_HIGHLIGHT_GAIN_GAMMA <
	ui_type = "drag";
	ui_min = 0.0;
    ui_max = 4.0;
    ui_step = 0.01;
    ui_label = "Highlight Gain Treshold";
    ui_tooltip = "A simple Gamma operation on the Luminance mask.\nIncrease/decrease ranges of highlight boosted.";
    ui_category = "Input";
> = 1.0;


uniform int UIHELP <
	ui_type = "radio";
	ui_label = " ";	
	ui_text ="Used to boost imagery after AgX. Do not abuse of it.";
	ui_category = "Output (Post AgX)";
>;

uniform float PUNCH_EXPOSURE <
	ui_type = "drag";
	ui_min = -5.0;
    ui_max = 5.0;
    ui_step = 0.01;
    ui_label = "Punchy Exposure";
    ui_tooltip = "Post display conversion. Applied Last.";
    ui_category = "Output (Post AgX)";
    ui_category_closed = true;
> = 0.0;

uniform float PUNCH_SATURATION <
	ui_type = "drag";
	ui_min = 0.5;
    ui_max = 3;
    ui_step = 0.01;
    ui_label = "Punchy Saturation";
    ui_tooltip = "Post display conversion.";
    ui_category = "Output (Post AgX)";
    ui_category_closed = true;
> = 1.0;

uniform float PUNCH_GAMMA <
	ui_type = "drag";
	ui_min = 0.001;
    ui_max = 2.0;
    ui_step = 0.01;
    ui_label = "Punchy Gamma";
    ui_tooltip = "Post display conversion.";
    ui_category = "Output (Post AgX)";
    ui_category_closed = true;
> = 1.3;

uniform bool DEBUG_A <
    ui_label = "Use OCIO log";
    ui_tooltip = "Use OCIO similar implementation (lg2 allocation transform). Should not provide difference.";
    ui_category = "DEBUG";
    ui_category_closed = true;
> = false;

uniform bool DEBUG_B <
    ui_label = "Apply Outset";
    ui_tooltip = "Opposite of inset (applied during AgX Log). Not used on the first AgX versions but will be on te future one :eyes:";
    ui_category = "DEBUG";
    ui_category_closed = true;
> = false;


texture LUTTex < source = "AgX-default_contrast.lut.png"; > { Width = LUT_DIMENSIONS.x; Height = LUT_DIMENSIONS.y; Format = RGBA8; };
sampler LUTSampler {Texture = LUTTex; Format = RGBA8;};


static const float3 luma_coefs_bt709 = float3(0.2126, 0.7152, 0.0722);
static const float3x3 agx_compressed_matrix = float3x3(
    0.84247906, 0.0784336, 0.07922375,
    0.04232824, 0.87846864, 0.07916613,
    0.04237565, 0.0784336, 0.87914297
);
static const float3x3 agx_compressed_matrix_inverse = float3x3(
    1.1968790, -0.09802088, -0.09902975,
    -0.05289685, 1.15190313, -0.09896118,
    -0.05297163, -0.09804345, 1.15107368
);

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


/* --------------------------------------------------------------------------------
// PROCESSES
-------------------------------------------------------------------------------- */

float3 applyIDT(float3 Image)
/*
    Convert input to workspace colorspace.
*/
{

    if (INPUT_COLORSPACE == 0) Image = cctf_decoding_sRGB(Image);
    if (INPUT_COLORSPACE == 1) Image = cctf_decoding_pow2_2(Image);

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
    Image = mul(agx_compressed_matrix, Image);

    if (DEBUG_A)
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
    Image = mul(agx_compressed_matrix_inverse, Image);
    return Image;
}

float3 applyODT(float3 Image)
/*
    Apply Agx to display conversion.
    For now hardcoded to sRGB display.

    :param color: linear - sRGB data.

*/
{
    Image = cctf_encoding_pow2_2(Image);
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


void PS_Main(float4 vpos : SV_Position, float2 TexCoord : TEXCOORD, out float3 Image : SV_Target)
/*
    The whole image processing pipeline.
*/
{
    Image = tex2D(ReShade::BackBuffer, TexCoord).rgb;

    // An intersting note : initially I had all of this in a separate "technique pass", but I got some clamping issue
    // that took me hell to figure out, so I got back to one "pass" with multipel functions that now works.
    Image = applyIDT(Image);
    Image = applyAgXLog(Image);
    Image = applyAgXLUT(Image);
    if (DEBUG_B)
        Image = applyOutset(Image);
    Image = applyODT(Image);
    Image = applyLookPunchy(Image);

}


technique AgX_processing
{
    pass Main
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Main;
    }
}
