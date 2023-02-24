import logging
import colour
import argparse

from obs_codegen.entitities import Whitepoint
from obs_codegen.entitities import Cat
from obs_codegen.entitities import AssemblyColorspace
from obs_codegen.entitities import ColorspaceGamut
from obs_codegen.entitities import TransferFunction
from obs_codegen.hlsl.generator import HlslGenerator
from obs_codegen.lua.generator import LuaGenerator

logger = logging.getLogger(__name__)


def generate(language: str):

    illuminant1931: dict = colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]

    transfer_function_power_2_2 = TransferFunction("Power 2.2")
    transfer_function_sRGB_EOTF = TransferFunction("sRGB EOTF")
    transfer_function_BT709 = TransferFunction("BT.709")
    transfer_function_DCIP3 = TransferFunction("DCI-P3")
    transfer_function_Display_P3 = TransferFunction("Display P3")
    transfer_function_Adobe_RGB_1998 = TransferFunction("Adobe RGB 1998")
    transfer_function_BT2020 = TransferFunction("BT.2020")

    transfer_function_list = [
        transfer_function_power_2_2,
        transfer_function_sRGB_EOTF,
        transfer_function_BT709,
        transfer_function_DCIP3,
        transfer_function_Display_P3,
        transfer_function_Adobe_RGB_1998,
        transfer_function_BT2020,
    ]

    # fmt: off
    colorspace_gamut_sRGB = ColorspaceGamut.fromColourColorspaceName("sRGB")
    colorspace_gamut_DCIP3 = ColorspaceGamut.fromColourColorspaceName("DCI-P3")
    colorspace_gamut_Display_P3 = ColorspaceGamut.fromColourColorspaceName("Display P3")
    colorspace_gamut_Adobe_RGB_1998 = ColorspaceGamut.fromColourColorspaceName("Adobe RGB (1998)")
    colorspace_gamut_ITUR_BT_2020 = ColorspaceGamut.fromColourColorspaceName("ITU-R BT.2020")
    colorspace_gamut_list = [
        colorspace_gamut_sRGB,
        colorspace_gamut_DCIP3,
        colorspace_gamut_Display_P3,
        colorspace_gamut_Adobe_RGB_1998,
        colorspace_gamut_ITUR_BT_2020,
    ]
    # fmt: on

    whitepoint_D60 = Whitepoint("D60", illuminant1931["D60"])
    whitepoint_D65 = Whitepoint("D65", illuminant1931["D65"])
    whitepoint_DCIP3 = Whitepoint("DCI-P3", illuminant1931["DCI-P3"])
    whitepoint_list = [whitepoint_D60, whitepoint_D65, whitepoint_DCIP3]

    assembly_colorspace_Passthrough = AssemblyColorspace(
        "Passthrough",
        None,
        None,
        None,
    )
    assembly_colorspace_sRGB_Display_EOTF = AssemblyColorspace(
        "sRGB Display (EOTF)",
        colorspace_gamut_sRGB,
        whitepoint_D65,
        transfer_function_sRGB_EOTF,
    )
    assembly_colorspace_sRGB_Display_2_2 = AssemblyColorspace(
        "sRGB Display (2.2)",
        colorspace_gamut_sRGB,
        whitepoint_D65,
        transfer_function_power_2_2,
    )
    assembly_colorspace_sRGB_Linear = AssemblyColorspace(
        "sRGB Linear",
        colorspace_gamut_sRGB,
        whitepoint_D65,
        None,
    )
    assembly_colorspace_BT_709_Display_2_4 = AssemblyColorspace(
        "BT.709 Display (2.4)",
        colorspace_gamut_sRGB,
        whitepoint_D65,
        transfer_function_BT709,
    )
    assembly_colorspace_DCIP3_Display_2_6 = AssemblyColorspace(
        "DCI-P3 Display (2.6)",
        colorspace_gamut_DCIP3,
        whitepoint_DCIP3,
        transfer_function_DCIP3,
    )
    assembly_colorspace_DCIP3_D65_Display_2_6 = AssemblyColorspace(
        "DCI-P3 D65 Display (2.6)",
        colorspace_gamut_DCIP3,
        whitepoint_D65,
        transfer_function_DCIP3,
    )
    assembly_colorspace_DCIP3_D60_Display_2_6 = AssemblyColorspace(
        "DCI-P3 D60 Display (2.6)",
        colorspace_gamut_DCIP3,
        whitepoint_D60,
        transfer_function_DCIP3,
    )
    assembly_colorspace_Apple_Display_P3 = AssemblyColorspace(
        "Apple Display P3",
        colorspace_gamut_Display_P3,
        whitepoint_DCIP3,
        transfer_function_Display_P3,
    )
    assembly_colorspace_Adobe_RGB_1998_Display = AssemblyColorspace(
        "Adobe RGB 1998 Display",
        colorspace_gamut_Adobe_RGB_1998,
        whitepoint_D65,
        transfer_function_Adobe_RGB_1998,
    )
    assembly_colorspace_BT_2020_Display_OETF = AssemblyColorspace(
        "BT.2020 Display (OETF)",
        colorspace_gamut_ITUR_BT_2020,
        whitepoint_D65,
        transfer_function_BT2020,
    )
    assembly_colorspace_BT_2020_Linear = AssemblyColorspace(
        "BT.2020 Linear",
        colorspace_gamut_ITUR_BT_2020,
        whitepoint_D65,
        None,
    )
    assembly_colorspace_DCIP3_Linear = AssemblyColorspace(
        "DCI-P3 Linear",
        colorspace_gamut_DCIP3,
        whitepoint_DCIP3,
        None,
    )
    assembly_colorspace_list = [
        assembly_colorspace_Passthrough,
        assembly_colorspace_sRGB_Display_EOTF,
        assembly_colorspace_sRGB_Display_2_2,
        assembly_colorspace_sRGB_Linear,
        assembly_colorspace_BT_709_Display_2_4,
        assembly_colorspace_DCIP3_Display_2_6,
        assembly_colorspace_DCIP3_D65_Display_2_6,
        assembly_colorspace_DCIP3_D60_Display_2_6,
        assembly_colorspace_Apple_Display_P3,
        assembly_colorspace_Adobe_RGB_1998_Display,
        assembly_colorspace_BT_2020_Display_OETF,
        assembly_colorspace_BT_2020_Linear,
        assembly_colorspace_DCIP3_Linear,
    ]

    generator_kwargs = {
        "colorspaces_gamut": colorspace_gamut_list,
        "whitepoints": whitepoint_list,
        "cats": [
            Cat("XYZ Scaling"),
            Cat("Bradford"),
            Cat("CAT02"),
            Cat("Von Kries"),
        ],
        "colorspaces_assemblies": assembly_colorspace_list,
        "transfer_functions": transfer_function_list,
    }

    if language == "hlsl":

        generator_hlsl = HlslGenerator(**generator_kwargs)
        print(generator_hlsl.generateCode())

    elif language == "lua":

        generator_lua = LuaGenerator(**generator_kwargs)
        print(generator_lua.generateCode())

    else:
        raise ValueError(f"Unsupported {language=}")

    return


def cli():

    parser = argparse.ArgumentParser(
        description="OBS code generator. Just print in console."
    )
    parser.add_argument(
        "language",
        choices=["hlsl", "lua"],
        help="For which language shoudl teh code be generated",
    )
    args = parser.parse_args()
    language: str = args.language.lower()

    generate(language=language)


if __name__ == "__main__":

    cli()
