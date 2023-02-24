import dataclasses
import itertools
import logging

import colour

from obs_codegen.c import HLSL_INDENT as INDENT
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
    variable_def = f"#define {variable_name} float3x3({convert3x3MatrixToHlslStr(matrix_cat, True)})\n"
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
    out_str += f"#define matrix_{colorspace.safe_name}_to_XYZ float3x3({convert3x3MatrixToHlslStr(matrix, True)})\n"
    matrix = colorspace.matrix_from_XYZ
    out_str += f"#define matrix_{colorspace.safe_name}_from_XYZ float3x3({convert3x3MatrixToHlslStr(matrix, True)})\n"
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
        str_cctf = self._generateTransferFunctionBlock()
        str_matrices = self._generateMatricesBlock()
        str_cat = self._generateCatBlock()
        str_colorspace = self._generateColorspacesBlock()

        return (
            "// region WARNING code is procedurally generated\n"
            f"{str_cctf}\n\n{str_cat}\n\n{str_matrices}\n\n{str_colorspace}\n"
            "// endregion\n"
        )

    def _generateTransferFunctionBlock(self) -> str:

        out_str = ""
        out_str += "\n"

        for transfer_function in self.transfer_functions:

            out_str += f"uniform int {transfer_function.id_variable_name} = {transfer_function.id};  // {transfer_function.name}\n"

        for cctf_mode in ["decoding", "encoding"]:

            out_str += "\n\n"
            out_str += f"float3 apply_cctf_{cctf_mode}(float3 color, int cctf_id){{\n"

            for transfer_function in self.transfer_functions:

                skip = not transfer_function.has_decoding and cctf_mode == "decoding"
                if skip:
                    continue

                skip = not transfer_function.has_encoding and cctf_mode == "encoding"
                if skip:
                    continue

                out_str += INDENT
                out_str += f"if (cctf_id == {transfer_function.id_variable_name: <25})"
                out_str += (
                    f" return cctf_{cctf_mode}_{transfer_function.safe_name}(color);\n"
                )

            out_str += f"{INDENT}return color;\n"
            out_str += "}"

        return out_str

    def _generateMatricesBlock(self) -> str:

        out_str = generateCommentHeader("Matrices")
        out_str += "\n"

        for colorspace in self.colorspaces_gamut:

            out_str += processColorspaceMatrix(colorspace) + "\n"

        out_str += "\n"

        for colorspace in self.colorspaces_gamut:
            out_str += f"uniform int {colorspace.id_variable_name} = {colorspace.id};\n"

        for gamut_direction in ["to_XYZ", "from_XYZ"]:

            out_str += "\n\n"
            out_str += f"float3x3 get_gamut_matrix_{gamut_direction}(int gamutid){{\n"

            for colorspace in self.colorspaces_gamut:
                out_str += INDENT
                out_str += f"if (gamutid == {colorspace.id_variable_name: <25})"
                out_str += f" return matrix_{colorspace.safe_name}_{gamut_direction};\n"

            out_str += f"{INDENT}return matrix_identity_3x3;\n"

            out_str += "}"

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
            out_str += f"uniform int {cat.id_variable_name} = {cat.id};\n"

        out_str += "\n"

        for whitepoint in self.whitepoints:
            out_str += (
                f"uniform int whitepointid_{whitepoint.safe_name} = {whitepoint.id};\n"
            )

        out_str += "\n\n"
        out_str += "float3x3 get_chromatic_adaptation_transform_matrix(int cat_id, int whitepoint_source, int whitepoint_target){\n"

        for cat_variable_id, cat_variable in cat_variable_dict.items():
            out_str += INDENT
            out_str += f"if (cat_id == {cat_variable_id[0]} && whitepoint_source == {cat_variable_id[1]} && whitepoint_target == {cat_variable_id[2]})"
            out_str += f" return {cat_variable.name};\n"

        out_str += f"{INDENT}return matrix_identity_3x3;\n"
        out_str += "}"

        return out_str

    def _generateColorspacesBlock(self) -> str:

        out_str = generateCommentHeader("Colorspaces")
        out_str += "\n"

        out_str += "struct Colorspace{\n"
        out_str += (
            f"{INDENT}int gamut_id;\n"
            f"{INDENT}int whitepoint_id;\n"
            f"{INDENT}int cctf_id;\n"
        )
        out_str += "};\n\n"

        for assembly_colorspace in self.colorspaces_assemblies:

            out_str += f"uniform int {assembly_colorspace.id_variable_name} = {assembly_colorspace.id};\n"

        out_str += "\n"
        out_str += "Colorspace getColorspaceFromId(int colorspace_id){\n"

        out_str += f"\n{INDENT}Colorspace colorspace;\n\n"

        for assembly_colorspace in self.colorspaces_assemblies:

            out_str += INDENT
            out_str += (
                f"if (colorspace_id == {assembly_colorspace.id_variable_name}){{\n"
            )
            if assembly_colorspace.gamut:
                id_value = assembly_colorspace.gamut.id_variable_name
            else:
                id_value = -1
            out_str += f"{INDENT * 2}colorspace.gamut_id = {id_value};\n"

            if assembly_colorspace.whitepoint:
                id_value = assembly_colorspace.whitepoint.id_variable_name
            else:
                id_value = -1
            out_str += f"{INDENT * 2}colorspace.whitepoint_id = {id_value};\n"

            if assembly_colorspace.cctf:
                id_value = assembly_colorspace.cctf.id_variable_name
            else:
                id_value = -1
            out_str += f"{INDENT * 2}colorspace.cctf_id = {id_value};\n"

            out_str += f"{INDENT}}};\n"

        out_str += f"{INDENT}return colorspace;\n}}"
        return out_str
