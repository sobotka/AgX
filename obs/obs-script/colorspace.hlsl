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

#define matrix_identity_3x3 float3x3(\
    1.0, 0.0, 0.0,\
    0.0, 1.0, 0.0,\
    0.0, 0.0, 1.0\
)

float3 powsafe(float3 color, float power){
  // pow() but safe for NaNs/negatives
  return pow(abs(color), power) * sign(color);
}

float3 apply_matrix(float3 color, float3x3 inputMatrix){
  // seems you can't just use mul() with OBS, and we have to split per component like that :
  float r = dot(color, inputMatrix[0]);
	float g = dot(color, inputMatrix[1]);
	float b = dot(color, inputMatrix[2]);
  return float3(r, g, b);
}

float get_luminance(float3 image){
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
  float luma = get_luminance(color);
  return lerp(luma, color, saturationAmount);
}

/* --------------------------------------------------------------------------------
Transfer functions
-------------------------------------------------------------------------------- */

float3 cctf_log2_normalized_from_open_domain(float3 color, float minimum_ev, float maximum_ev)
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
float3 cctf_log2_ocio_transform(float3 color)
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

float3 cctf_decoding_sRGB_EOTF(float3 color){
    // ref[2]
    return (color <= 0.04045) ? (color / 12.92) : (powsafe((color + 0.055) / 1.055, 2.4));
}

float3 cctf_encoding_sRGB_EOTF(float3 color){
    // ref[2]
    return (color <= 0.0031308) ? (color * 12.92) : (1.055 * powsafe(color, 1/2.4) - 0.055);
}

float3 cctf_decoding_Power_2_2(float3 color){return powsafe(color, 2.2);}

float3 cctf_encoding_Power_2_2(float3 color){return powsafe(color, 1/2.2);}

float3 cctf_decoding_BT_709(float3 color){return powsafe(color, 2.4);}

float3 cctf_encoding_BT_709(float3 color){return powsafe(color, 1/2.4);}

float3 cctf_decoding_DCIP3(float3 color){return powsafe(color, 2.6);}

float3 cctf_encoding_DCIP3(float3 color){return powsafe(color, 1/2.6);}

float3 cctf_encoding_BT_2020(float3 color){return (color < 0.0181) ? color * 4.5 : 1.0993 * powsafe(color, 0.45) - (1.0993 - 1);}

float3 cctf_decoding_BT_2020(float3 color){return (color < cctf_encoding_BT_2020(0.0181)) ? color / 4.5 : powsafe((color + (1.0993 - 1)) / 1.0993, 1 / 0.45) ;}

float3 cctf_decoding_Display_P3(float3 color){return cctf_decoding_sRGB_EOTF(color);}

float3 cctf_encoding_Display_P3(float3 color){return cctf_encoding_sRGB_EOTF(color);}

float3 cctf_decoding_Adobe_RGB_1998(float3 color){return powsafe(color, 2.19921875);}

float3 cctf_encoding_Adobe_RGB_1998(float3 color){return powsafe(color, 1/2.19921875);}

// region WARNING code is procedurally generated

uniform int cctf_id_Power_2_2 = 0;  // Power 2.2
uniform int cctf_id_sRGB_EOTF = 1;  // sRGB EOTF
uniform int cctf_id_BT_709 = 2;  // BT.709
uniform int cctf_id_DCIP3 = 3;  // DCI-P3
uniform int cctf_id_Display_P3 = 4;  // Display P3
uniform int cctf_id_Adobe_RGB_1998 = 5;  // Adobe RGB 1998
uniform int cctf_id_BT_2020 = 6;  // BT.2020


float3 apply_cctf_decoding(float3 color, int cctf_id){
    if (cctf_id == cctf_id_Power_2_2        ) return cctf_decoding_Power_2_2(color);
    if (cctf_id == cctf_id_sRGB_EOTF        ) return cctf_decoding_sRGB_EOTF(color);
    if (cctf_id == cctf_id_BT_709           ) return cctf_decoding_BT_709(color);
    if (cctf_id == cctf_id_DCIP3            ) return cctf_decoding_DCIP3(color);
    if (cctf_id == cctf_id_Display_P3       ) return cctf_decoding_Display_P3(color);
    if (cctf_id == cctf_id_Adobe_RGB_1998   ) return cctf_decoding_Adobe_RGB_1998(color);
    if (cctf_id == cctf_id_BT_2020          ) return cctf_decoding_BT_2020(color);
    return color;
}

float3 apply_cctf_encoding(float3 color, int cctf_id){
    if (cctf_id == cctf_id_Power_2_2        ) return cctf_encoding_Power_2_2(color);
    if (cctf_id == cctf_id_sRGB_EOTF        ) return cctf_encoding_sRGB_EOTF(color);
    if (cctf_id == cctf_id_BT_709           ) return cctf_encoding_BT_709(color);
    if (cctf_id == cctf_id_DCIP3            ) return cctf_encoding_DCIP3(color);
    if (cctf_id == cctf_id_Display_P3       ) return cctf_encoding_Display_P3(color);
    if (cctf_id == cctf_id_Adobe_RGB_1998   ) return cctf_encoding_Adobe_RGB_1998(color);
    if (cctf_id == cctf_id_BT_2020          ) return cctf_encoding_BT_2020(color);
    return color;
}

/* --------------------------------------------------------------------------------
Chromatic Adaptation Transforms
-------------------------------------------------------------------------------- */

#define matrix_cat_XYZ_Scaling_D60_to_D65 float3x3(\
    0.997749312, 0.0, 0.0,\
    0.0, 1.0, 0.0,\
    0.0, 0.0, 1.079011464\
)
#define matrix_cat_XYZ_Scaling_D60_to_DCIP3 float3x3(\
    0.939100313, 0.0, 0.0,\
    0.0, 1.0, 0.0,\
    0.0, 0.0, 0.945611705\
)
#define matrix_cat_XYZ_Scaling_D65_to_D60 float3x3(\
    1.002255765, 0.0, 0.0,\
    0.0, 1.0, 0.0,\
    0.0, 0.0, 0.926774212\
)
#define matrix_cat_XYZ_Scaling_D65_to_DCIP3 float3x3(\
    0.941218703, 0.0, 0.0,\
    0.0, 1.0, 0.0,\
    0.0, 0.0, 0.876368543\
)
#define matrix_cat_XYZ_Scaling_DCIP3_to_D60 float3x3(\
    1.064848969, 0.0, 0.0,\
    0.0, 1.0, 0.0,\
    0.0, 0.0, 1.05751652\
)
#define matrix_cat_XYZ_Scaling_DCIP3_to_D65 float3x3(\
    1.062452326, 0.0, 0.0,\
    0.0, 1.0, 0.0,\
    0.0, 0.0, 1.141072449\
)
#define matrix_cat_Bradford_D60_to_D65 float3x3(\
    0.987323904, -0.006062169, 0.015845876,\
    -0.007531959, 1.001832321, 0.005293338,\
    0.00305302, -0.005064257, 1.081147527\
)
#define matrix_cat_Bradford_D60_to_DCIP3 float3x3(\
    0.964265012, -0.021300233, -0.002647012,\
    -0.033122492, 1.030598686, 0.000944999,\
    -0.003057139, 0.006720893, 0.941838177\
)
#define matrix_cat_Bradford_D65_to_D60 float3x3(\
    1.012931026, 0.006054132, -0.0148757,\
    0.007630325, 0.998191932, -0.004999018,\
    -0.002824644, 0.004658585, 0.924961741\
)
#define matrix_cat_Bradford_D65_to_DCIP3 float3x3(\
    0.976578897, -0.015436265, -0.016686022,\
    -0.025689666, 1.028539168, -0.003785174,\
    -0.005705746, 0.011077866, 0.871176159\
)
#define matrix_cat_Bradford_DCIP3_to_D60 float3x3(\
    1.037804611, 0.021430283, 0.002895221,\
    0.033351213, 0.971004834, -0.00088053,\
    0.003130647, -0.006859463, 1.061769201\
)
#define matrix_cat_Bradford_DCIP3_to_D65 float3x3(\
    1.024496728, 0.015163541, 0.019688522,\
    0.025612193, 0.972586306, 0.004716352,\
    0.006384231, -0.012268083, 1.147942445\
)
#define matrix_cat_CAT02_D60_to_D65 float3x3(\
    0.988317991, -0.007816256, 0.016645551,\
    -0.00564353, 0.998686699, 0.00662762,\
    0.00035077, 0.001116791, 1.077573915\
)
#define matrix_cat_CAT02_D60_to_DCIP3 float3x3(\
    0.979655622, -0.035093475, -0.003506859,\
    -0.024670911, 1.024631944, -0.001120007,\
    0.000239512, -0.000975875, 0.946352523\
)
#define matrix_cat_CAT02_D65_to_D60 float3x3(\
    1.011870978, 0.007936977, -0.015679437,\
    0.005720259, 1.001366784, -0.00624727,\
    -0.000335311, -0.001040394, 0.928022164\
)
#define matrix_cat_CAT02_D65_to_DCIP3 float3x3(\
    0.991085525, -0.027362287, -0.018395654,\
    -0.019102244, 1.025837747, -0.007053718,\
    -8.0549e-05, -0.001959887, 0.878238458\
)
#define matrix_cat_CAT02_DCIP3_to_D60 float3x3(\
    1.021647216, 0.034994893, 0.003827292,\
    0.024598791, 0.976803896, 0.001247201,\
    -0.000233203, 0.00099842, 1.056688999\
)
#define matrix_cat_CAT02_DCIP3_to_D65 float3x3(\
    1.009516172, 0.026967753, 0.021362003,\
    0.018799243, 0.97533018, 0.008227297,\
    0.000134542, 0.002179032, 1.138663236\
)
#define matrix_cat_Von_Kries_D60_to_D65 float3x3(\
    0.995663132, -0.014998519, 0.016829124,\
    -0.001647481, 1.001234102, 0.000332195,\
    0.0, 0.0, 1.079011464\
)
#define matrix_cat_Von_Kries_D60_to_DCIP3 float3x3(\
    0.9888443, -0.038575341, -0.0087295,\
    -0.004237228, 1.003172521, 0.000855893,\
    0.0, 0.0, 0.945611705\
)
#define matrix_cat_Von_Kries_D65_to_D60 float3x3(\
    1.004380654, 0.015045655, -0.015669755,\
    0.001652658, 0.998792176, -0.000333274,\
    0.0, 0.0, 0.926774212\
)
#define matrix_cat_Von_Kries_D65_to_DCIP3 float3x3(\
    0.993112333, -0.023650939, -0.023572367,\
    -0.002597888, 1.001897113, 0.000525285,\
    0.0, 0.0, 0.876368543\
)
#define matrix_cat_Von_Kries_DCIP3_to_D60 float3x3(\
    1.011448214, 0.038893569, 0.009302073,\
    0.004272183, 0.997001792, -0.000862968,\
    0.0, 0.0, 1.05751652\
)
#define matrix_cat_Von_Kries_DCIP3_to_D65 float3x3(\
    1.00699762, 0.023771342, 0.027071751,\
    0.002611113, 0.998168118, -0.000528057,\
    0.0, 0.0, 1.141072449\
)

uniform int catid_XYZ_Scaling = 0;
uniform int catid_Bradford = 1;
uniform int catid_CAT02 = 2;
uniform int catid_Von_Kries = 3;

uniform int whitepointid_D60 = 0;
uniform int whitepointid_D65 = 1;
uniform int whitepointid_DCIP3 = 2;


float3x3 get_chromatic_adaptation_transform_matrix(int cat_id, int whitepoint_source, int whitepoint_target){
    if (cat_id == 0 && whitepoint_source == 0 && whitepoint_target == 1) return matrix_cat_XYZ_Scaling_D60_to_D65;
    if (cat_id == 0 && whitepoint_source == 0 && whitepoint_target == 2) return matrix_cat_XYZ_Scaling_D60_to_DCIP3;
    if (cat_id == 0 && whitepoint_source == 1 && whitepoint_target == 0) return matrix_cat_XYZ_Scaling_D65_to_D60;
    if (cat_id == 0 && whitepoint_source == 1 && whitepoint_target == 2) return matrix_cat_XYZ_Scaling_D65_to_DCIP3;
    if (cat_id == 0 && whitepoint_source == 2 && whitepoint_target == 0) return matrix_cat_XYZ_Scaling_DCIP3_to_D60;
    if (cat_id == 0 && whitepoint_source == 2 && whitepoint_target == 1) return matrix_cat_XYZ_Scaling_DCIP3_to_D65;
    if (cat_id == 1 && whitepoint_source == 0 && whitepoint_target == 1) return matrix_cat_Bradford_D60_to_D65;
    if (cat_id == 1 && whitepoint_source == 0 && whitepoint_target == 2) return matrix_cat_Bradford_D60_to_DCIP3;
    if (cat_id == 1 && whitepoint_source == 1 && whitepoint_target == 0) return matrix_cat_Bradford_D65_to_D60;
    if (cat_id == 1 && whitepoint_source == 1 && whitepoint_target == 2) return matrix_cat_Bradford_D65_to_DCIP3;
    if (cat_id == 1 && whitepoint_source == 2 && whitepoint_target == 0) return matrix_cat_Bradford_DCIP3_to_D60;
    if (cat_id == 1 && whitepoint_source == 2 && whitepoint_target == 1) return matrix_cat_Bradford_DCIP3_to_D65;
    if (cat_id == 2 && whitepoint_source == 0 && whitepoint_target == 1) return matrix_cat_CAT02_D60_to_D65;
    if (cat_id == 2 && whitepoint_source == 0 && whitepoint_target == 2) return matrix_cat_CAT02_D60_to_DCIP3;
    if (cat_id == 2 && whitepoint_source == 1 && whitepoint_target == 0) return matrix_cat_CAT02_D65_to_D60;
    if (cat_id == 2 && whitepoint_source == 1 && whitepoint_target == 2) return matrix_cat_CAT02_D65_to_DCIP3;
    if (cat_id == 2 && whitepoint_source == 2 && whitepoint_target == 0) return matrix_cat_CAT02_DCIP3_to_D60;
    if (cat_id == 2 && whitepoint_source == 2 && whitepoint_target == 1) return matrix_cat_CAT02_DCIP3_to_D65;
    if (cat_id == 3 && whitepoint_source == 0 && whitepoint_target == 1) return matrix_cat_Von_Kries_D60_to_D65;
    if (cat_id == 3 && whitepoint_source == 0 && whitepoint_target == 2) return matrix_cat_Von_Kries_D60_to_DCIP3;
    if (cat_id == 3 && whitepoint_source == 1 && whitepoint_target == 0) return matrix_cat_Von_Kries_D65_to_D60;
    if (cat_id == 3 && whitepoint_source == 1 && whitepoint_target == 2) return matrix_cat_Von_Kries_D65_to_DCIP3;
    if (cat_id == 3 && whitepoint_source == 2 && whitepoint_target == 0) return matrix_cat_Von_Kries_DCIP3_to_D60;
    if (cat_id == 3 && whitepoint_source == 2 && whitepoint_target == 1) return matrix_cat_Von_Kries_DCIP3_to_D65;
    return matrix_identity_3x3;
}

/* --------------------------------------------------------------------------------
Matrices
-------------------------------------------------------------------------------- */

// sRGB
#define matrix_sRGB_to_XYZ float3x3(\
    0.4124, 0.3576, 0.1805,\
    0.2126, 0.7152, 0.0722,\
    0.0193, 0.1192, 0.9505\
)
#define matrix_sRGB_from_XYZ float3x3(\
    3.2406, -1.5372, -0.4986,\
    -0.9689, 1.8758, 0.0415,\
    0.0557, -0.204, 1.057\
)

// DCI-P3
#define matrix_DCIP3_to_XYZ float3x3(\
    0.445169816, 0.277134409, 0.17228267,\
    0.209491678, 0.721595254, 0.068913068,\
    -0.0, 0.04706056, 0.907355394\
)
#define matrix_DCIP3_from_XYZ float3x3(\
    2.72539403, -1.018003006, -0.440163195,\
    -0.795168026, 1.689732055, 0.022647191,\
    0.041241891, -0.087639019, 1.100929379\
)

// Display P3
#define matrix_Display_P3_to_XYZ float3x3(\
    0.486570949, 0.265667693, 0.198217285,\
    0.228974564, 0.691738522, 0.079286914,\
    -0.0, 0.045113382, 1.043944369\
)
#define matrix_Display_P3_from_XYZ float3x3(\
    2.493496912, -0.931383618, -0.402710784,\
    -0.82948897, 1.76266406, 0.023624686,\
    0.03584583, -0.076172389, 0.956884524\
)

// Adobe RGB (1998)
#define matrix_Adobe_RGB_1998_to_XYZ float3x3(\
    0.57667, 0.18556, 0.18823,\
    0.29734, 0.62736, 0.07529,\
    0.02703, 0.07069, 0.99134\
)
#define matrix_Adobe_RGB_1998_from_XYZ float3x3(\
    2.04159, -0.56501, -0.34473,\
    -0.96924, 1.87597, 0.04156,\
    0.01344, -0.11836, 1.01517\
)

// ITU-R BT.2020
#define matrix_ITUR_BT_2020_to_XYZ float3x3(\
    0.636958048, 0.144616904, 0.168880975,\
    0.262700212, 0.677998072, 0.059301716,\
    0.0, 0.028072693, 1.060985058\
)
#define matrix_ITUR_BT_2020_from_XYZ float3x3(\
    1.716651188, -0.355670784, -0.253366281,\
    -0.666684352, 1.616481237, 0.015768546,\
    0.017639857, -0.042770613, 0.942103121\
)


uniform int gamutid_sRGB = 0;
uniform int gamutid_DCIP3 = 1;
uniform int gamutid_Display_P3 = 2;
uniform int gamutid_Adobe_RGB_1998 = 3;
uniform int gamutid_ITUR_BT_2020 = 4;


float3x3 get_gamut_matrix_to_XYZ(int gamutid){
    if (gamutid == gamutid_sRGB             ) return matrix_sRGB_to_XYZ;
    if (gamutid == gamutid_DCIP3            ) return matrix_DCIP3_to_XYZ;
    if (gamutid == gamutid_Display_P3       ) return matrix_Display_P3_to_XYZ;
    if (gamutid == gamutid_Adobe_RGB_1998   ) return matrix_Adobe_RGB_1998_to_XYZ;
    if (gamutid == gamutid_ITUR_BT_2020     ) return matrix_ITUR_BT_2020_to_XYZ;
    return matrix_identity_3x3;
}

float3x3 get_gamut_matrix_from_XYZ(int gamutid){
    if (gamutid == gamutid_sRGB             ) return matrix_sRGB_from_XYZ;
    if (gamutid == gamutid_DCIP3            ) return matrix_DCIP3_from_XYZ;
    if (gamutid == gamutid_Display_P3       ) return matrix_Display_P3_from_XYZ;
    if (gamutid == gamutid_Adobe_RGB_1998   ) return matrix_Adobe_RGB_1998_from_XYZ;
    if (gamutid == gamutid_ITUR_BT_2020     ) return matrix_ITUR_BT_2020_from_XYZ;
    return matrix_identity_3x3;
}

/* --------------------------------------------------------------------------------
Colorspaces
-------------------------------------------------------------------------------- */

struct Colorspace{
    int gamut_id;
    int whitepoint_id;
    int cctf_id;
};

uniform int colorspaceid_Passthrough = 0;
uniform int colorspaceid_sRGB_Display_EOTF = 1;
uniform int colorspaceid_sRGB_Display_2_2 = 2;
uniform int colorspaceid_sRGB_Linear = 3;
uniform int colorspaceid_BT_709_Display_2_4 = 4;
uniform int colorspaceid_DCIP3_Display_2_6 = 5;
uniform int colorspaceid_DCIP3_D65_Display_2_6 = 6;
uniform int colorspaceid_DCIP3_D60_Display_2_6 = 7;
uniform int colorspaceid_Apple_Display_P3 = 8;
uniform int colorspaceid_Adobe_RGB_1998_Display = 9;
uniform int colorspaceid_BT_2020_Display_OETF = 10;
uniform int colorspaceid_BT_2020_Linear = 11;

Colorspace getColorspaceFromId(int colorspace_id){

    Colorspace colorspace;

    if (colorspace_id == colorspaceid_Passthrough){
        colorspace.gamut_id = -1;
        colorspace.whitepoint_id = -1;
        colorspace.cctf_id = -1;
    };
    if (colorspace_id == colorspaceid_sRGB_Display_EOTF){
        colorspace.gamut_id = gamutid_sRGB;
        colorspace.whitepoint_id = whitepointid_D65;
        colorspace.cctf_id = cctf_id_sRGB_EOTF;
    };
    if (colorspace_id == colorspaceid_sRGB_Display_2_2){
        colorspace.gamut_id = gamutid_sRGB;
        colorspace.whitepoint_id = whitepointid_D65;
        colorspace.cctf_id = cctf_id_Power_2_2;
    };
    if (colorspace_id == colorspaceid_sRGB_Linear){
        colorspace.gamut_id = gamutid_sRGB;
        colorspace.whitepoint_id = whitepointid_D65;
        colorspace.cctf_id = -1;
    };
    if (colorspace_id == colorspaceid_BT_709_Display_2_4){
        colorspace.gamut_id = gamutid_sRGB;
        colorspace.whitepoint_id = whitepointid_D65;
        colorspace.cctf_id = cctf_id_BT_709;
    };
    if (colorspace_id == colorspaceid_DCIP3_Display_2_6){
        colorspace.gamut_id = gamutid_sRGB;
        colorspace.whitepoint_id = whitepointid_DCIP3;
        colorspace.cctf_id = cctf_id_DCIP3;
    };
    if (colorspace_id == colorspaceid_DCIP3_D65_Display_2_6){
        colorspace.gamut_id = gamutid_sRGB;
        colorspace.whitepoint_id = whitepointid_D65;
        colorspace.cctf_id = cctf_id_DCIP3;
    };
    if (colorspace_id == colorspaceid_DCIP3_D60_Display_2_6){
        colorspace.gamut_id = gamutid_sRGB;
        colorspace.whitepoint_id = whitepointid_D60;
        colorspace.cctf_id = cctf_id_DCIP3;
    };
    if (colorspace_id == colorspaceid_Apple_Display_P3){
        colorspace.gamut_id = gamutid_Display_P3;
        colorspace.whitepoint_id = whitepointid_DCIP3;
        colorspace.cctf_id = cctf_id_Display_P3;
    };
    if (colorspace_id == colorspaceid_Adobe_RGB_1998_Display){
        colorspace.gamut_id = gamutid_Adobe_RGB_1998;
        colorspace.whitepoint_id = whitepointid_D65;
        colorspace.cctf_id = cctf_id_Adobe_RGB_1998;
    };
    if (colorspace_id == colorspaceid_BT_2020_Display_OETF){
        colorspace.gamut_id = gamutid_ITUR_BT_2020;
        colorspace.whitepoint_id = whitepointid_D65;
        colorspace.cctf_id = cctf_id_BT_2020;
    };
    if (colorspace_id == colorspaceid_BT_2020_Linear){
        colorspace.gamut_id = gamutid_ITUR_BT_2020;
        colorspace.whitepoint_id = whitepointid_D65;
        colorspace.cctf_id = -1;
    };
    return colorspace;
}
// endregion

float3 convertColorspaceToColorspace(float3 color, int sourceColorspaceId, int targetColorspaceId){

    if (sourceColorspaceId == colorspaceid_Passthrough)
        return color;
    if (targetColorspaceId == colorspaceid_Passthrough)
        return color;
    if (sourceColorspaceId == targetColorspaceId)
        return color;

    Colorspace source_colorspace = getColorspaceFromId(sourceColorspaceId);
    Colorspace target_colorspace = getColorspaceFromId(targetColorspaceId);

    color = apply_cctf_decoding(color, source_colorspace.cctf_id);

    // apply Chromatic adaptation transform if any
    if (source_colorspace.whitepoint_id != target_colorspace.whitepoint_id && (source_colorspace.whitepoint_id != -1) && (target_colorspace.whitepoint_id != -1)){
        color = apply_matrix(color, get_chromatic_adaptation_transform_matrix(CAT_METHOD, source_colorspace.whitepoint_id, target_colorspace.whitepoint_id));
    }

    if (source_colorspace.gamut_id != target_colorspace.gamut_id && (source_colorspace.gamut_id != -1) && (target_colorspace.gamut_id != -1)){
        color = apply_matrix(color, get_gamut_matrix_to_XYZ(source_colorspace.gamut_id));
        color = apply_matrix(color, get_gamut_matrix_from_XYZ(target_colorspace.gamut_id));
    }
    color = apply_cctf_encoding(color, target_colorspace.cctf_id);

    return color;

};
