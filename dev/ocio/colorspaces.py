import logging
from typing import Literal
from typing import Optional
from typing import Union

import colour
import numpy

logger = logging.getLogger(__name__)


DECIMALS = 12


"""-------------------------------------------------------------------------------------
Utilities to compute the matrix for OCIO
"""


def matrix_3x3_to_4x4(matrix: numpy.ndarray) -> numpy.ndarray:
    """
    Convert a 3x3 matrix to a 4x4 matrix as such :
    [[ value  value  value  0. ]
     [ value  value  value  0. ]
     [ value  value  value  0. ]
     [ 0.     0.     0.    1. ]]

    Returns:
        4x4 matrix
    """

    output = numpy.append(matrix, [[0], [0], [0]], axis=1)
    output = numpy.append(output, [[0, 0, 0, 1]], axis=0)

    return output


def matrix_format_oneline(matrix: numpy.ndarray) -> list[float]:
    """
    Convert the matrix to a one line list (no nested list).

    Returns:
        list: matrix as a single depth list.
    """

    output = numpy.concatenate(matrix).tolist()
    return output


def matrix_format_ocio(matrix: numpy.ndarray) -> list[float]:
    """
    Format the given 3x3 matrix to an OCIO parameters complient list.

    Args:
        matrix: 3x3 matrix
    Returns:
        list: 4x4 matrix in a single line list.
    """
    return matrix_format_oneline(matrix_3x3_to_4x4(matrix))


def matrix_whitepoint_cat(
    source_whitepoint: numpy.ndarray,
    target_whitepoint: numpy.ndarray,
    cat: str = "Bradford",
) -> numpy.ndarray:
    """Return the matrix to perform a chromatic adaptation with the given
    parameters.

    Args:
        source_whitepoint: source whitepoint name as xy coordinates
        target_whitepoint: target whitepoint name as xy coordinates
        cat: chromatic adaptation transform method to use.

    Returns:
        chromatic adaptation matrix from test viewing conditions
         to reference viewing conditions. A 3x3 matrix.
    """

    matrix = colour.adaptation.matrix_chromatic_adaptation_VonKries(
        colour.xy_to_XYZ(source_whitepoint),
        colour.xy_to_XYZ(target_whitepoint),
        transform=cat,
    )

    return matrix


def matrix_primaries_transform_ocio(
    source: Union[colour.RGB_Colourspace, Literal["XYZ"]],
    target: Union[colour.RGB_Colourspace, Literal["XYZ"]],
    source_whitepoint: Optional[numpy.ndarray] = None,
    target_whitepoint: Optional[numpy.ndarray] = None,
    cat: str = "Bradford",
) -> list[float]:
    """
    By given a source and target colorspace, return the corresponding
    colorspace conversion matrix.
    You can use "XYZ" as a source or target.

    Args:
        source: source colorspace, use "XYZ" for CIE-XYZ.
        target: target colorspace, use "XYZ" for CIE-XYZ.
        source_whitepoint: whitepoint coordinates as [x, y]
        target_whitepoint: whitepoint coordinates as [x, y]
        cat: chromatic adaptation transform
    Returns:
        4x4 matrix in a single line list.
    """
    matrix_cat = None
    if source_whitepoint is not None and target_whitepoint is not None:
        matrix_cat = matrix_whitepoint_cat(
            source_whitepoint=source_whitepoint,
            target_whitepoint=target_whitepoint,
            cat=cat,
        )

    if source == "XYZ" or target == "XYZ":
        if target == "XYZ":
            matrix = source.matrix_RGB_to_XYZ

            if matrix_cat is not None:
                matrix = numpy.dot(matrix_cat, matrix)

        else:
            matrix = target.matrix_XYZ_to_RGB

            if matrix_cat is not None:
                matrix = numpy.dot(matrix, matrix_cat)

    else:
        matrix = source.matrix_RGB_to_XYZ

        if matrix_cat is not None:
            matrix = numpy.dot(matrix_cat, source.matrix_RGB_to_XYZ)

        matrix = numpy.dot(target.matrix_XYZ_to_RGB, matrix)

    matrix = matrix.round(DECIMALS)
    return matrix_format_ocio(matrix)


"""-------------------------------------------------------------------------------------
Conversions
"""


def xyz_to_ap0():
    source = "XYZ"
    target: colour.RGB_Colourspace = colour.RGB_COLOURSPACES["ACES2065-1"]
    target.use_derived_transformation_matrices(True)

    illum_1931 = colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]
    whitepoint_d65 = illum_1931["D65"]

    matrix = matrix_primaries_transform_ocio(
        source=source,
        target=target,
        source_whitepoint=whitepoint_d65,
        target_whitepoint=target.whitepoint,
    )
    return matrix


def xyz_to_ap1():
    source = "XYZ"
    target: colour.RGB_Colourspace = colour.RGB_COLOURSPACES["ACEScg"]
    target.use_derived_transformation_matrices(True)

    illum_1931 = colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]
    whitepoint_d65 = illum_1931["D65"]

    matrix = matrix_primaries_transform_ocio(
        source=source,
        target=target,
        source_whitepoint=whitepoint_d65,
        target_whitepoint=target.whitepoint,
    )
    return matrix


def srgb_to_xyz():
    source: colour.RGB_Colourspace = colour.RGB_COLOURSPACES["sRGB"]
    source.use_derived_transformation_matrices(True)
    target = "XYZ"

    illum_1931 = colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]
    whitepoint_d65 = illum_1931["D65"]

    matrix = matrix_primaries_transform_ocio(
        source=source,
        target=target,
        source_whitepoint=source.whitepoint,
        target_whitepoint=whitepoint_d65,
    )
    return matrix


def srgb_to_p3():
    source: colour.RGB_Colourspace = colour.RGB_COLOURSPACES["sRGB"]
    source.use_derived_transformation_matrices(True)
    target: colour.RGB_Colourspace = colour.RGB_COLOURSPACES["DCI-P3"]
    target.use_derived_transformation_matrices(True)

    matrix = matrix_primaries_transform_ocio(
        source=source,
        target=target,
        source_whitepoint=source.whitepoint,
        target_whitepoint=target.whitepoint,
    )
    return matrix


def ap0_to_srgb():
    source: colour.RGB_Colourspace = colour.RGB_COLOURSPACES["ACES2065-1"]
    source.use_derived_transformation_matrices(True)
    target: colour.RGB_Colourspace = colour.RGB_COLOURSPACES["ITU-R BT.709"]
    target.use_derived_transformation_matrices(True)

    matrix = matrix_primaries_transform_ocio(
        source=source,
        target=target,
        source_whitepoint=source.whitepoint,
        target_whitepoint=target.whitepoint,
    )
    return matrix


if __name__ == "__main__":
    print(f"{xyz_to_ap0()=}")
    print(f"{xyz_to_ap1()=}")
    print(f"{srgb_to_xyz()=}")
    print(f"{srgb_to_p3()=}")
    print(f"{ap0_to_srgb()=}")
