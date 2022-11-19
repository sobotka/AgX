import dataclasses
import itertools
import logging

import colour

from obs_codegen.generator import BaseGenerator
from obs_codegen.entitities import Whitepoint
from obs_codegen.entitities import Cat
from obs_codegen.entitities import ColorspaceGamut
from .util import convert3x3MatrixToHlslStr
from .util import generateCommentHeader

logger = logging.getLogger(__name__)


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
class HlslGenerator(BaseGenerator):
    """
    Generate HLSL code as a string following the given input attributes.
    """

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
