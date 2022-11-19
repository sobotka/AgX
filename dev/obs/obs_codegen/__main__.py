import logging
import colour

from obs_codegen.entitities import Whitepoint
from obs_codegen.entitities import Cat
from obs_codegen.entitities import AssemblyColorspace
from obs_codegen.entitities import ColorspaceGamut
from obs_codegen.hlsl.generator import HlslGenerator

logger = logging.getLogger(__name__)


def main():

    illuminant1931: dict = colour.CCS_ILLUMINANTS["CIE 1931 2 Degree Standard Observer"]

    generator_kwargs = {
        "colorspaces_gamut": [
            ColorspaceGamut.fromColourColorspaceName("sRGB"),
            ColorspaceGamut.fromColourColorspaceName("DCI-P3"),
            ColorspaceGamut.fromColourColorspaceName("Display P3"),
            ColorspaceGamut.fromColourColorspaceName("Adobe RGB (1998)"),
            ColorspaceGamut.fromColourColorspaceName("ITU-R BT.2020"),
        ],
        "whitepoints": [
            Whitepoint("D60", illuminant1931["D60"]),
            Whitepoint("D65", illuminant1931["D65"]),
            Whitepoint("DCI-P3", illuminant1931["DCI-P3"]),
        ],
        "cats": [
            Cat("XYZ Scaling"),
            Cat("Bradford"),
            Cat("CAT02"),
            Cat("Von Kries"),
        ],
        "colorspaces_assemblies": [
            AssemblyColorspace("Passthrough"),
            AssemblyColorspace("sRGB Display (EOTF)"),
            AssemblyColorspace("sRGB Display (2.2)"),
            AssemblyColorspace("sRGB Linear"),
            AssemblyColorspace("BT.709 Display (2.4)"),
            AssemblyColorspace("DCI-P3 Display (2.6)"),
            AssemblyColorspace("Apple Display P3"),
        ],
    }

    generator_hlsl = HlslGenerator(**generator_kwargs)

    print(generator_hlsl.generateCode())
    return


if __name__ == "__main__":
    main()
