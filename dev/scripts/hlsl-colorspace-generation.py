"""
Using colour & python to generate HLSL code for colorspace conversions.
"""
from typing import Optional, List

import colour
import numpy

ROUND_THRESHOLD = 9


def convert3x3MatrixToHlslStr(matrix: numpy.ndarray) -> str:
    """

    Args:
        matrix: 3x3 matrix as numpy array

    Returns:
        partial HLSL variable declaration.
    """
    return (
        "{\n"
        f"  {round(matrix[0][0], ROUND_THRESHOLD)}, {round(matrix[0][1], ROUND_THRESHOLD)}, {round(matrix[0][2], ROUND_THRESHOLD)},\n"
        f"  {round(matrix[1][0], ROUND_THRESHOLD)}, {round(matrix[1][1], ROUND_THRESHOLD)}, {round(matrix[1][2], ROUND_THRESHOLD)},\n"
        f"  {round(matrix[2][0], ROUND_THRESHOLD)}, {round(matrix[2][1], ROUND_THRESHOLD)}, {round(matrix[2][2], ROUND_THRESHOLD)}\n"
        "};\n"
    )


def processWhitepoint(whitepoint: numpy.ndarray, whitepointName: str) -> str:
    """

    Args:
        whitepoint:
        whitepointName:

    Returns:
        valid HLSL code snippet
    """
    array = colour.xy_to_XYZ(whitepoint)
    whitepointName = whitepointName.replace("-", "")
    return (
        f"uniform float3 whitepoint_{whitepointName} = "
        f"{{{round(array[0], ROUND_THRESHOLD)}, {round(array[1], ROUND_THRESHOLD)}, {round(array[2], ROUND_THRESHOLD)}}};"
    )


def processColorspaceMatrix(colorspace: colour.RGB_Colourspace) -> str:
    """

    Args:
        colorspace:

    Returns:
        valid HLSL code snippet
    """
    out_str = ""
    out_str += f"// {colorspace.name}\n"
    colorspaceName = colour.utilities.slugify(colorspace.name).replace("-", "")
    matrix = colorspace.matrix_RGB_to_XYZ
    out_str += f"uniform float3x3 matrix_{colorspaceName}_to_XYZ = {convert3x3MatrixToHlslStr(matrix)}"
    matrix = colorspace.matrix_XYZ_to_RGB
    out_str += f"uniform float3x3 matrix_{colorspaceName}_from_XYZ = {convert3x3MatrixToHlslStr(matrix)}"
    return out_str


def generateCommentHeader(title: str, description: Optional[str] = None) -> str:
    """
    Generate an HLSL comment block to summarize the code that can be found under.
    """
    max_length = 80

    out_str = "/* "
    out_str += "-" * max_length + "\n"
    out_str += title + "\n"
    if description:
        out_str += "\n"
        out_str += description + "\n"
    out_str += "-" * max_length + " */\n"
    return out_str


class Generator:
    """
    Generate HLSL code as a string following the given input attributes.
    """

    def __init__(self, colorspaceNames, whitepointNames, catNames):

        self.colorspaceNames = colorspaceNames
        self.whitepointNames = whitepointNames
        self.catNames = catNames

        self.colorspaceToProcessList: List[colour.RGB_Colourspace] = [
            colour.RGB_COLOURSPACES[colorspaceName]
            for colorspaceName in colorspaceNames
        ]

        illuminant1931: dict = colour.CCS_ILLUMINANTS[
            "CIE 1931 2 Degree Standard Observer"
        ]

        self.whitepointToProcessDict: dict[str, numpy.ndarray] = {}
        """
        {"whitepoint Name": whitepoint coordinates as [x, y]}
        """
        for whitepoint_name in whitepointNames:
            self.whitepointToProcessDict[whitepoint_name] = illuminant1931[
                whitepoint_name
            ]
        # append whitepoint from processed colorspaces
        for colorspace in self.colorspaceToProcessList:

            if self.whitepointToProcessDict.get(colorspace.whitepoint_name) is not None:
                continue

            self.whitepointToProcessDict[
                colorspace.whitepoint_name
            ] = colorspace.whitepoint

        self.catToProcessDict: dict[str, numpy.ndarray] = {
            catName: colour.CHROMATIC_ADAPTATION_TRANSFORMS[catName]
            for catName in self.catNames
        }
        """
        {"CAT Name": CAT 3x3 matrix}
        """

    def generateCode(self) -> str:
        """
        Returns:
            valid HLSL code snippet
        """

        str_colorspace = self._generateMatricesBlock()
        str_whitepoint = self._generateWhitepointsBlock()
        str_cat = self._generateCatBlock()

        return f"{str_cat}\n\n{str_whitepoint}\n\n{str_colorspace}"

    def _generateMatricesBlock(self) -> str:

        out_str = generateCommentHeader("Matrices")
        out_str += "\n"

        for colorspace in self.colorspaceToProcessList:

            out_str += processColorspaceMatrix(colorspace) + "\n"

        return out_str

    def _generateWhitepointsBlock(self) -> str:

        out_str = generateCommentHeader("Whitepoints", "xy values converted to XYZ")
        out_str += "\n"

        for whitepoint_name, whitepoint in self.whitepointToProcessDict.items():
            out_str += processWhitepoint(whitepoint, whitepoint_name) + "\n"

        return out_str

    def _generateCatBlock(self) -> str:

        out_str = generateCommentHeader("Chromatic Adaptation Transforms")
        out_str += "\n"

        for cat_name, cat in self.catToProcessDict.items():
            cat_name_slug = colour.utilities.slugify(cat_name).replace("-", "")
            out_str += f"uniform float3x3 matrix_cat_{cat_name_slug} = {convert3x3MatrixToHlslStr(cat)}"

        return out_str


def main():

    generator = Generator(
        colorspaceNames=[
            "sRGB",
            "DCI-P3",
            "Display P3",
            "Adobe RGB (1998)",
            "ITU-R BT.2020",
        ],
        whitepointNames=[
            "D60",
        ],
        catNames=[
            "Bradford",
            "CAT02",
            "Von Kries",
        ],
    )
    print(generator.generateCode())
    return


if __name__ == "__main__":
    main()
