import logging
from pathlib import Path

import colour

logger = logging.getLogger(__name__)


def generate_and_save_sRGB_LUT(targetPath: Path):

    lut_size = 4096
    lut_domain = [0.0, 1.0]

    array = colour.LUT1D.linear_table(lut_size, lut_domain)
    array = colour.models.RGB_COLOURSPACE_sRGB.cctf_decoding(array)

    lut = colour.LUT1D(
        table=array,
        name="sRGB EOTF decoding",
        domain=[0.0, 1.0],
        comments=[
            "sRGB IEC 61966-2-1 2.2 Exponent Reference EOTF Display. Decoding function."
        ],
    )

    colour.write_LUT(lut, str(targetPath))

    logger.info(f"[generate_and_save_sRGB_LUT] Finished writting {targetPath}")
    return


if __name__ == "__main__":

    logging.basicConfig(
        level=logging.DEBUG,
        format="{levelname: <7} | {asctime} [{name}]{message}",
        style="{",
    )

    _targetPath = Path() / ".." / ".." / "ocio" / "LUTs" / "sRGB-EOTF-inverse.spi1d"
    _targetPath = _targetPath.absolute().resolve()

    generate_and_save_sRGB_LUT(targetPath=_targetPath)
