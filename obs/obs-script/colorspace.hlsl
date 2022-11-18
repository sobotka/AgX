/*
RGB Colorspace related objects


References
----------

All data without explicit reference can assumed to be extracted/generated from `colour-science` python library.

- [1] https://github.com/sobotka/AgX-S2O3/blob/main/AgX.py
- [2] https://github.com/colour-science/colour/blob/develop/colour/models/rgb/transfer_functions/srgb.py#L99
*/


float3 powsafe(float3 color, float power)
// pow() but safe for NaNs/negatives
{
    return pow(abs(color), power) * sign(color);
}


/* --------------------------------------------------------------------------------
Transfer functions
-------------------------------------------------------------------------------- */

float3 convertOpenDomainToNormalizedLog2(float3 color, float minimum_ev, float maximum_ev)
/*
    Output log domain encoded data.

    Similar to OCIO lg2 AllocationTransform.

    ref[1]
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

float3 cctf_decoding_sRGB(float3 color){
    // ref[2]
    return (color <= 0.04045) ? (color / 12.92) : (powsafe((color + 0.055) / 1.055, 2.4));
}

float3 cctf_encoding_sRGB(float3 color){
    // ref[2]
    return (color <= 0.0031308) ? (color * 12.92) : (1.055 * powsafe(color, 1/2.4) - 0.055);
}

float3 cctf_decoding_pow2_2(float3 color){return powsafe(color, 2.2);}

float3 cctf_encoding_pow2_2(float3 color){return powsafe(color, 1/2.2);}

float3 cctf_decoding_bt709(float3 color){return powsafe(color, 2.4);}

float3 cctf_encoding_bt709(float3 color){return powsafe(color, 1/2.4);}


/* --------------------------------------------------------------------------------
Chromatic Adaptation Transforms
-------------------------------------------------------------------------------- */

uniform float3x3 matrix_cat_bradford = {
  0.8951, 0.2664, -0.1614,
  -0.7502, 1.7135, 0.0367,
  0.0389, -0.0685, 1.0296
};
uniform float3x3 matrix_cat_cat02 = {
  0.7328, 0.4296, -0.1624,
  -0.7036, 1.6975, 0.0061,
  0.003, 0.0136, 0.9834
};
uniform float3x3 matrix_cat_vonkries = {
  0.40024, 0.7076, -0.08081,
  -0.2263, 1.16532, 0.0457,
  0.0, 0.0, 0.91822
};


/* --------------------------------------------------------------------------------
Whitepoints

xy values converted to XYZ
-------------------------------------------------------------------------------- */

uniform float3 whitepoint_D60 = {0.952599932, 1.0, 1.009310639};
uniform float3 whitepoint_D65 = {0.950455927, 1.0, 1.089057751};
uniform float3 whitepoint_DCIP3 = {0.894586895, 1.0, 0.954415954};


/* --------------------------------------------------------------------------------
Matrices
-------------------------------------------------------------------------------- */

// sRGB
uniform float3x3 matrix_srgb_to_XYZ = {
  0.4124, 0.3576, 0.1805,
  0.2126, 0.7152, 0.0722,
  0.0193, 0.1192, 0.9505
};
uniform float3x3 matrix_srgb_from_XYZ = {
  3.2406, -1.5372, -0.4986,
  -0.9689, 1.8758, 0.0415,
  0.0557, -0.204, 1.057
};

// DCI-P3
uniform float3x3 matrix_dcip3_to_XYZ = {
  0.445169816, 0.277134409, 0.17228267,
  0.209491678, 0.721595254, 0.068913068,
  -0.0, 0.04706056, 0.907355394
};
uniform float3x3 matrix_dcip3_from_XYZ = {
  2.72539403, -1.018003006, -0.440163195,
  -0.795168026, 1.689732055, 0.022647191,
  0.041241891, -0.087639019, 1.100929379
};

// Display P3
uniform float3x3 matrix_displayp3_to_XYZ = {
  0.486570949, 0.265667693, 0.198217285,
  0.228974564, 0.691738522, 0.079286914,
  -0.0, 0.045113382, 1.043944369
};
uniform float3x3 matrix_displayp3_from_XYZ = {
  2.493496912, -0.931383618, -0.402710784,
  -0.82948897, 1.76266406, 0.023624686,
  0.03584583, -0.076172389, 0.956884524
};

// Adobe RGB (1998)
uniform float3x3 matrix_adobergb1998_to_XYZ = {
  0.57667, 0.18556, 0.18823,
  0.29734, 0.62736, 0.07529,
  0.02703, 0.07069, 0.99134
};
uniform float3x3 matrix_adobergb1998_from_XYZ = {
  2.04159, -0.56501, -0.34473,
  -0.96924, 1.87597, 0.04156,
  0.01344, -0.11836, 1.01517
};

// ITU-R BT.2020
uniform float3x3 matrix_iturbt2020_to_XYZ = {
  0.636958048, 0.144616904, 0.168880975,
  0.262700212, 0.677998072, 0.059301716,
  0.0, 0.028072693, 1.060985058
};
uniform float3x3 matrix_iturbt2020_from_XYZ = {
  1.716651188, -0.355670784, -0.253366281,
  -0.666684352, 1.616481237, 0.015768546,
  0.017639857, -0.042770613, 0.942103121
};


/* --------------------------------------------------------------------------------
Colorspaces
-------------------------------------------------------------------------------- */


float3 convertColorspaceToColorspace(float3 color, int sourceColorspaceId, int targetColorspaceId){
    return color;
};
