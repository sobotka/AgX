/*
RGB Colorspace related objects


References
----------

All data without explicit reference can assumed to be extracted/generated from `colour-science` python library.

- [1] https://github.com/sobotka/AgX-S2O3/blob/main/AgX.py
- [2] https://github.com/colour-science/colour/blob/develop/colour/models/rgb/transfer_functions/srgb.py#L99
*/


uniform int CAT_METHOD = 0; // See Chromatic Adapatation transform section for availables ids


#define luma_coefs_bt709 float3(0.2126, 0.7152, 0.0722)


float3 powsafe(float3 color, float power){
  // pow() but safe for NaNs/negatives
  return pow(abs(color), power) * sign(color);
}

float3 applyMatrix(float3 color, float3x3 inputMatrix){
  // seems you can't just use mul() with OBS, and we have to split per component like that :
  float r = dot(color, inputMatrix[0]);
	float g = dot(color, inputMatrix[1]);
	float b = dot(color, inputMatrix[2]);
  return float3(r, g, b);
}

float getLuminance(float3 image){
  // Return approximative perceptive luminance of the image.
  return dot(image, luma_coefs_bt709);
}

float3 saturation(float3 color, float saturationAmount){
  /*

      Increase color saturation of the given color data.

      :param color: expected sRGB primaries input
      :oaram saturationAmount: expected 0-1 range with 1=neutral, 0=no saturation.

      -- ref[2] [4]
  */
  float luma = getLuminance(color);
  return lerp(luma, color, saturationAmount);
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

float3 cctf_decoding_dcip3(float3 color){return powsafe(color, 2.6);}

float3 cctf_encoding_dcip3(float3 color){return powsafe(color, 1/2.6);}

float3 cctf_decoding_bt2020(float3 color){return color;} // TODO

float3 cctf_encoding_bt2020(float3 color){return color;}  // TODO

/* --------------------------------------------------------------------------------
Chromatic Adaptation Transforms
-------------------------------------------------------------------------------- */

#define matrix_cat_xyzscaling_d60_to_d65 float3x3(\
  0.997749312, 0.0, 0.0,\
  0.0, 1.0, 0.0,\
  0.0, 0.0, 1.079011464\
)
#define matrix_cat_xyzscaling_d60_to_dcip3 float3x3(\
  0.939100313, 0.0, 0.0,\
  0.0, 1.0, 0.0,\
  0.0, 0.0, 0.945611705\
)
#define matrix_cat_xyzscaling_d65_to_d60 float3x3(\
  1.002255765, 0.0, 0.0,\
  0.0, 1.0, 0.0,\
  0.0, 0.0, 0.926774212\
)
#define matrix_cat_xyzscaling_d65_to_dcip3 float3x3(\
  0.941218703, 0.0, 0.0,\
  0.0, 1.0, 0.0,\
  0.0, 0.0, 0.876368543\
)
#define matrix_cat_xyzscaling_dcip3_to_d60 float3x3(\
  1.064848969, 0.0, 0.0,\
  0.0, 1.0, 0.0,\
  0.0, 0.0, 1.05751652\
)
#define matrix_cat_xyzscaling_dcip3_to_d65 float3x3(\
  1.062452326, 0.0, 0.0,\
  0.0, 1.0, 0.0,\
  0.0, 0.0, 1.141072449\
)
#define matrix_cat_bradford_d60_to_d65 float3x3(\
  0.987323904, -0.006062169, 0.015845876,\
  -0.007531959, 1.001832321, 0.005293338,\
  0.00305302, -0.005064257, 1.081147527\
)
#define matrix_cat_bradford_d60_to_dcip3 float3x3(\
  0.964265012, -0.021300233, -0.002647012,\
  -0.033122492, 1.030598686, 0.000944999,\
  -0.003057139, 0.006720893, 0.941838177\
)
#define matrix_cat_bradford_d65_to_d60 float3x3(\
  1.012931026, 0.006054132, -0.0148757,\
  0.007630325, 0.998191932, -0.004999018,\
  -0.002824644, 0.004658585, 0.924961741\
)
#define matrix_cat_bradford_d65_to_dcip3 float3x3(\
  0.976578897, -0.015436265, -0.016686022,\
  -0.025689666, 1.028539168, -0.003785174,\
  -0.005705746, 0.011077866, 0.871176159\
)
#define matrix_cat_bradford_dcip3_to_d60 float3x3(\
  1.037804611, 0.021430283, 0.002895221,\
  0.033351213, 0.971004834, -0.00088053,\
  0.003130647, -0.006859463, 1.061769201\
)
#define matrix_cat_bradford_dcip3_to_d65 float3x3(\
  1.024496728, 0.015163541, 0.019688522,\
  0.025612193, 0.972586306, 0.004716352,\
  0.006384231, -0.012268083, 1.147942445\
)
#define matrix_cat_cat02_d60_to_d65 float3x3(\
  0.988317991, -0.007816256, 0.016645551,\
  -0.00564353, 0.998686699, 0.00662762,\
  0.00035077, 0.001116791, 1.077573915\
)
#define matrix_cat_cat02_d60_to_dcip3 float3x3(\
  0.979655622, -0.035093475, -0.003506859,\
  -0.024670911, 1.024631944, -0.001120007,\
  0.000239512, -0.000975875, 0.946352523\
)
#define matrix_cat_cat02_d65_to_d60 float3x3(\
  1.011870978, 0.007936977, -0.015679437,\
  0.005720259, 1.001366784, -0.00624727,\
  -0.000335311, -0.001040394, 0.928022164\
)
#define matrix_cat_cat02_d65_to_dcip3 float3x3(\
  0.991085525, -0.027362287, -0.018395654,\
  -0.019102244, 1.025837747, -0.007053718,\
  -8.0549e-05, -0.001959887, 0.878238458\
)
#define matrix_cat_cat02_dcip3_to_d60 float3x3(\
  1.021647216, 0.034994893, 0.003827292,\
  0.024598791, 0.976803896, 0.001247201,\
  -0.000233203, 0.00099842, 1.056688999\
)
#define matrix_cat_cat02_dcip3_to_d65 float3x3(\
  1.009516172, 0.026967753, 0.021362003,\
  0.018799243, 0.97533018, 0.008227297,\
  0.000134542, 0.002179032, 1.138663236\
)
#define matrix_cat_vonkries_d60_to_d65 float3x3(\
  0.995663132, -0.014998519, 0.016829124,\
  -0.001647481, 1.001234102, 0.000332195,\
  0.0, 0.0, 1.079011464\
)
#define matrix_cat_vonkries_d60_to_dcip3 float3x3(\
  0.9888443, -0.038575341, -0.0087295,\
  -0.004237228, 1.003172521, 0.000855893,\
  0.0, 0.0, 0.945611705\
)
#define matrix_cat_vonkries_d65_to_d60 float3x3(\
  1.004380654, 0.015045655, -0.015669755,\
  0.001652658, 0.998792176, -0.000333274,\
  0.0, 0.0, 0.926774212\
)
#define matrix_cat_vonkries_d65_to_dcip3 float3x3(\
  0.993112333, -0.023650939, -0.023572367,\
  -0.002597888, 1.001897113, 0.000525285,\
  0.0, 0.0, 0.876368543\
)
#define matrix_cat_vonkries_dcip3_to_d60 float3x3(\
  1.011448214, 0.038893569, 0.009302073,\
  0.004272183, 0.997001792, -0.000862968,\
  0.0, 0.0, 1.05751652\
)
#define matrix_cat_vonkries_dcip3_to_d65 float3x3(\
  1.00699762, 0.023771342, 0.027071751,\
  0.002611113, 0.998168118, -0.000528057,\
  0.0, 0.0, 1.141072449\
)

uniform int catid_xyzscaling = 0;
uniform int catid_bradford = 1;
uniform int catid_cat02 = 2;
uniform int catid_vonkries = 3;

uniform int whitepointid_d60 = 0;
uniform int whitepointid_d65 = 1;
uniform int whitepointid_dcip3 = 2;


float3x3 getChromaticAdaptationTransformMatrix(int cat_name, int whitepoint_source, int whitepoint_target){
    if (cat_name == 0 && whitepoint_source == 0 && whitepoint_target == 1) return matrix_cat_xyzscaling_d60_to_d65;
    if (cat_name == 0 && whitepoint_source == 0 && whitepoint_target == 2) return matrix_cat_xyzscaling_d60_to_dcip3;
    if (cat_name == 0 && whitepoint_source == 1 && whitepoint_target == 0) return matrix_cat_xyzscaling_d65_to_d60;
    if (cat_name == 0 && whitepoint_source == 1 && whitepoint_target == 2) return matrix_cat_xyzscaling_d65_to_dcip3;
    if (cat_name == 0 && whitepoint_source == 2 && whitepoint_target == 0) return matrix_cat_xyzscaling_dcip3_to_d60;
    if (cat_name == 0 && whitepoint_source == 2 && whitepoint_target == 1) return matrix_cat_xyzscaling_dcip3_to_d65;
    if (cat_name == 1 && whitepoint_source == 0 && whitepoint_target == 1) return matrix_cat_bradford_d60_to_d65;
    if (cat_name == 1 && whitepoint_source == 0 && whitepoint_target == 2) return matrix_cat_bradford_d60_to_dcip3;
    if (cat_name == 1 && whitepoint_source == 1 && whitepoint_target == 0) return matrix_cat_bradford_d65_to_d60;
    if (cat_name == 1 && whitepoint_source == 1 && whitepoint_target == 2) return matrix_cat_bradford_d65_to_dcip3;
    if (cat_name == 1 && whitepoint_source == 2 && whitepoint_target == 0) return matrix_cat_bradford_dcip3_to_d60;
    if (cat_name == 1 && whitepoint_source == 2 && whitepoint_target == 1) return matrix_cat_bradford_dcip3_to_d65;
    if (cat_name == 2 && whitepoint_source == 0 && whitepoint_target == 1) return matrix_cat_cat02_d60_to_d65;
    if (cat_name == 2 && whitepoint_source == 0 && whitepoint_target == 2) return matrix_cat_cat02_d60_to_dcip3;
    if (cat_name == 2 && whitepoint_source == 1 && whitepoint_target == 0) return matrix_cat_cat02_d65_to_d60;
    if (cat_name == 2 && whitepoint_source == 1 && whitepoint_target == 2) return matrix_cat_cat02_d65_to_dcip3;
    if (cat_name == 2 && whitepoint_source == 2 && whitepoint_target == 0) return matrix_cat_cat02_dcip3_to_d60;
    if (cat_name == 2 && whitepoint_source == 2 && whitepoint_target == 1) return matrix_cat_cat02_dcip3_to_d65;
    if (cat_name == 3 && whitepoint_source == 0 && whitepoint_target == 1) return matrix_cat_vonkries_d60_to_d65;
    if (cat_name == 3 && whitepoint_source == 0 && whitepoint_target == 2) return matrix_cat_vonkries_d60_to_dcip3;
    if (cat_name == 3 && whitepoint_source == 1 && whitepoint_target == 0) return matrix_cat_vonkries_d65_to_d60;
    if (cat_name == 3 && whitepoint_source == 1 && whitepoint_target == 2) return matrix_cat_vonkries_d65_to_dcip3;
    if (cat_name == 3 && whitepoint_source == 2 && whitepoint_target == 0) return matrix_cat_vonkries_dcip3_to_d60;
    if (cat_name == 3 && whitepoint_source == 2 && whitepoint_target == 1) return matrix_cat_vonkries_dcip3_to_d65;
}

/* --------------------------------------------------------------------------------
Matrices
-------------------------------------------------------------------------------- */

// sRGB
#define matrix_srgb_to_XYZ float3x3(\
  0.4124, 0.3576, 0.1805,\
  0.2126, 0.7152, 0.0722,\
  0.0193, 0.1192, 0.9505\
)
#define matrix_srgb_from_XYZ float3x3(\
  3.2406, -1.5372, -0.4986,\
  -0.9689, 1.8758, 0.0415,\
  0.0557, -0.204, 1.057\
)

// DCI-P3
#define matrix_dcip3_to_XYZ float3x3(\
  0.445169816, 0.277134409, 0.17228267,\
  0.209491678, 0.721595254, 0.068913068,\
  -0.0, 0.04706056, 0.907355394\
)
#define matrix_dcip3_from_XYZ float3x3(\
  2.72539403, -1.018003006, -0.440163195,\
  -0.795168026, 1.689732055, 0.022647191,\
  0.041241891, -0.087639019, 1.100929379\
)

// Display P3
#define matrix_displayp3_to_XYZ float3x3(\
  0.486570949, 0.265667693, 0.198217285,\
  0.228974564, 0.691738522, 0.079286914,\
  -0.0, 0.045113382, 1.043944369\
)
#define matrix_displayp3_from_XYZ float3x3(\
  2.493496912, -0.931383618, -0.402710784,\
  -0.82948897, 1.76266406, 0.023624686,\
  0.03584583, -0.076172389, 0.956884524\
)

// Adobe RGB (1998)
#define matrix_adobergb1998_to_XYZ float3x3(\
  0.57667, 0.18556, 0.18823,\
  0.29734, 0.62736, 0.07529,\
  0.02703, 0.07069, 0.99134\
)
#define matrix_adobergb1998_from_XYZ float3x3(\
  2.04159, -0.56501, -0.34473,\
  -0.96924, 1.87597, 0.04156,\
  0.01344, -0.11836, 1.01517\
)

// ITU-R BT.2020
#define matrix_iturbt2020_to_XYZ float3x3(\
  0.636958048, 0.144616904, 0.168880975,\
  0.262700212, 0.677998072, 0.059301716,\
  0.0, 0.028072693, 1.060985058\
)
#define matrix_iturbt2020_from_XYZ float3x3(\
  1.716651188, -0.355670784, -0.253366281,\
  -0.666684352, 1.616481237, 0.015768546,\
  0.017639857, -0.042770613, 0.942103121\
)


/* --------------------------------------------------------------------------------
Colorspaces
-------------------------------------------------------------------------------- */


uniform int colorspaceid_Passthrough = 0;
uniform int colorspaceid_sRGB_Display_EOTF = 1;
uniform int colorspaceid_sRGB_Display_2_2 = 2;
uniform int colorspaceid_sRGB_Linear = 3;
uniform int colorspaceid_BT709_Display_2_4 = 4;
uniform int colorspaceid_DCIP3_Display_2_6 = 5;
uniform int colorspaceid_Display_P3 = 6; // Apple's P3


float3 convertColorspaceToColorspace(float3 color, int sourceColorspaceId, int targetColorspaceId){

    if (sourceColorspaceId == colorspaceid_Passthrough)
        return color;
    if (targetColorspaceId == colorspaceid_Passthrough)
        return color;
    if (sourceColorspaceId == targetColorspaceId)
        return color;

    float3 whitepoint_source;
    float3 whitepoint_target;

    if (sourceColorspaceId == colorspaceid_sRGB_Display_EOTF){
        whitepoint_source = whitepointid_d65;
        color = cctf_decoding_sRGB(color);
        color = applyMatrix(color, matrix_srgb_to_XYZ);
    }

    
    return color;

};
