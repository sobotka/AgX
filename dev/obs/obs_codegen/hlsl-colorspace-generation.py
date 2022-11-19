"""
Using colour & python to generate HLSL code for colorspace conversions.
"""
import itertools
import dataclasses
import re
from typing import Optional, List

import colour
import numpy

ROUND_THRESHOLD = 9


def slugify(string: str, preserve_case: bool = True) -> str:
    """
    Convert to code variable compatible name.
    """
    if not preserve_case:
        string = string.lower()

    output = string.replace("-", "")
    output = re.sub(r"\W", "_", output)
    output = re.sub(r"_{2,}", "_", output)
    output = output.rstrip("_")
    return output


def convert3x3MatrixToHlslStr(matrix: numpy.ndarray) -> str:
    """

    Args:
        matrix: 3x3 matrix as numpy array

    Returns:
        partial HLSL variable declaration.
    """
    return (
        "\\\n"
        f"  {round(matrix[0][0], ROUND_THRESHOLD)}, {round(matrix[0][1], ROUND_THRESHOLD)}, {round(matrix[0][2], ROUND_THRESHOLD)},\\\n"
        f"  {round(matrix[1][0], ROUND_THRESHOLD)}, {round(matrix[1][1], ROUND_THRESHOLD)}, {round(matrix[1][2], ROUND_THRESHOLD)},\\\n"
        f"  {round(matrix[2][0], ROUND_THRESHOLD)}, {round(matrix[2][1], ROUND_THRESHOLD)}, {round(matrix[2][2], ROUND_THRESHOLD)}\\\n"
    )


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


@dataclasses.dataclass
class ColorspaceGamut:

    name: str
    matrix_to_XYZ: numpy.ndarray
    matrix_from_XYZ: numpy.ndarray
    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __post_init__(self):
        self.safe_name = slugify(self.name)

    def __hash__(self):
        return hash(self.name)

    @classmethod
    def fromColourColorspaceName(cls, colorspace_name: str):
        colour_colorspace: colour.RGB_Colourspace = colour.RGB_COLOURSPACES[
            colorspace_name
        ]
        return cls(
            colour_colorspace.name,
            colour_colorspace.matrix_RGB_to_XYZ,
            colour_colorspace.matrix_XYZ_to_RGB,
        )


@dataclasses.dataclass
class Whitepoint:

    name: str
    coordinates: numpy.ndarray
    """
    CIE xy coordinates as a ndarray(2,)
    """

    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __post_init__(self):
        self.safe_name = slugify(self.name)

    def __hash__(self):
        return hash(self.name)


@dataclasses.dataclass
class Cat:

    name: str
    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __post_init__(self):
        self.safe_name = slugify(self.name)

    def __hash__(self):
        return hash(self.name)


@dataclasses.dataclass
class AssemblyColorspace:

    name: str
    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __post_init__(self):
        self.safe_name = slugify(self.name)

    def __hash__(self):
        return hash(self.name)


@dataclasses.dataclass
class HlslVariable:

    name: str
    definition: str


def processCat(
    whitepoint_source: Whitepoint,
    whitepoint_target: Whitepoint,
    cat: Cat,
) -> HlslVariable:

    matrix_cat = colour.adaptation.matrix_chromatic_adaptation_VonKries(
        colour.xy_to_XYZ(whitepoint_source.coordinates),
        colour.xy_to_XYZ(whitepoint_target.coordinates),
        cat.name,
    )

    variable_name = f"matrix_cat_{cat.safe_name}_{whitepoint_source.safe_name}_to_{whitepoint_target.safe_name}"
    variable_def = (
        f"#define {variable_name} float3x3({convert3x3MatrixToHlslStr(matrix_cat)})\n"
    )
    return HlslVariable(variable_name, variable_def)


def processColorspaceMatrix(colorspace: ColorspaceGamut) -> str:
    """
    Args:
        colorspace:

    Returns:
        valid HLSL code snippet
    """
    out_str = ""
    out_str += f"// {colorspace.name}\n"
    matrix = colorspace.matrix_to_XYZ
    out_str += f"#define matrix_{colorspace.safe_name}_to_XYZ float3x3({convert3x3MatrixToHlslStr(matrix)})\n"
    matrix = colorspace.matrix_from_XYZ
    out_str += f"#define matrix_{colorspace.safe_name}_from_XYZ float3x3({convert3x3MatrixToHlslStr(matrix)})\n"
    return out_str


@dataclasses.dataclass
class Generator:
    """
    Generate HLSL code as a string following the given input attributes.
    """

    colorspaces_gamut: list[ColorspaceGamut]
    whitepoints: list[Whitepoint]
    cats: list[Cat]
    colorspaces_assemblies: list[AssemblyColorspace]

    def generateCode(self) -> str:
        """
        Returns:
            valid HLSL code snippet
        """

        str_matrices = self._generateMatricesBlock()
        str_cat = self._generateCatBlock()
        str_colorspace = self._generateColorspacesBlock()

        return f"{str_cat}\n\n{str_matrices}\n\n{str_colorspace}"

    def _generateMatricesBlock(self) -> str:

        out_str = generateCommentHeader("Matrices")
        out_str += "\n"

        for colorspace in self.colorspaces_gamut:

            out_str += processColorspaceMatrix(colorspace) + "\n"

        return out_str

    def _generateCatBlock(self) -> str:

        out_str = generateCommentHeader("Chromatic Adaptation Transforms")
        out_str += "\n"

        whitepoint_combinaison_list = list(
            itertools.product(self.whitepoints, repeat=2)
        )

        cat_variable_dict = dict()

        for cat in self.cats:

            for whitepoint_combinaison in whitepoint_combinaison_list:

                whitepoint_source = whitepoint_combinaison[0]
                whitepoint_target = whitepoint_combinaison[1]

                if whitepoint_source == whitepoint_target:
                    continue

                cat_variable = processCat(whitepoint_source, whitepoint_target, cat)
                generated_id = (cat.id, whitepoint_source.id, whitepoint_target.id)
                cat_variable_dict[generated_id] = cat_variable

                out_str += cat_variable.definition
                continue

        out_str += "\n"

        for cat in self.cats:
            out_str += f"uniform int catid_{cat.safe_name} = {cat.id};\n"

        out_str += "\n"

        for whitepoint in self.whitepoints:
            out_str += (
                f"uniform int whitepointid_{whitepoint.safe_name} = {whitepoint.id};\n"
            )

        out_str += "\n\n"
        out_str += "float3x3 getChromaticAdaptationTransformMatrix(int cat_name, int whitepoint_source, int whitepoint_target){\n"

        for cat_variable_id, cat_variable in cat_variable_dict.items():
            out_str += f"    if (cat_name == {cat_variable_id[0]} && whitepoint_source == {cat_variable_id[1]} && whitepoint_target == {cat_variable_id[2]})"
            out_str += f" return {cat_variable.name};\n"

        out_str += "}"

        return out_str

    def _generateColorspacesBlock(self) -> str:

        out_str = generateCommentHeader("Colorspaces")
        out_str += "\n"

        for assembly_colorspace in self.colorspaces_assemblies:

            out_str += f"uniform int colorspaceid_{assembly_colorspace.safe_name} = {assembly_colorspace.id};\n"

        return out_str


def main():

    illuminant1931: dict = colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]

    generator = Generator(
        colorspaces_gamut=[
            ColorspaceGamut.fromColourColorspaceName("sRGB"),
            ColorspaceGamut.fromColourColorspaceName("DCI-P3"),
            ColorspaceGamut.fromColourColorspaceName("Display P3"),
            ColorspaceGamut.fromColourColorspaceName("Adobe RGB (1998)"),
            ColorspaceGamut.fromColourColorspaceName("ITU-R BT.2020"),
        ],
        whitepoints=[
            Whitepoint("D60", illuminant1931["D60"]),
            Whitepoint("D65", illuminant1931["D65"]),
            Whitepoint("DCI-P3", illuminant1931["DCI-P3"]),
        ],
        cats=[
            Cat("XYZ Scaling"),
            Cat("Bradford"),
            Cat("CAT02"),
            Cat("Von Kries"),
        ],
        colorspaces_assemblies=[
            AssemblyColorspace("Passthrough"),
            AssemblyColorspace("sRGB Display (EOTF)"),
            AssemblyColorspace("sRGB Display (2.2)"),
            AssemblyColorspace("sRGB Linear"),
            AssemblyColorspace("BT.709 Display (2.4)"),
            AssemblyColorspace("DCI-P3 Display (2.6)"),
            AssemblyColorspace("Apple Display P3"),
        ],
    )
    print(generator.generateCode())
    return


if __name__ == "__main__":
    main()
