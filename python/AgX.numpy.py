"""
AgX from Troy.S as a native python + numpy implementation.
(shameless "improved" copy of its existing work).

[performances]
- not suitable for realtime
- 0.73s of processing for a 1920x1080x3 EXR image

[dependencies]
python = ">2.7"
numpy = "*"
"""
__all__ = ("applyAgX",)
__version__ = "1.1.0"
__author__ = "Liam Collod <monsieurlixm@gmail.com>"

import numpy

try:  # python 2 compatibility. Only used in type hints.
    from typing import List, Union, Tuple
except ImportError:
    pass


# --------------------------------------------------------------------------------------
# Math/color grading
# --------------------------------------------------------------------------------------


def cdlPower(
    array,  # type: numpy.ndarray
    power,  # type: Union[float, Tuple[float, float, float]]
):
    # type: (...) -> numpy.ndarray
    """
    SRC: /src/OpenColorIO/ops/cdl/CDLOpCPU.cpp#L252
    SRC: /src/OpenColorIO/ops/gradingprimary/GradingPrimary.cpp#L194
    """
    out = abs(array) ** power
    out = out * numpy.copysign(1, array)
    return out


def saturate(
    array,  # type: numpy.ndarray
    saturation,  # type: Union[float, Tuple[float, float, float]]
    coefs=(0.2126, 0.7152, 0.0722),  # type: Tuple[float, float, float]
):
    # type: (...) -> numpy.ndarray
    """
    Increase color saturation (NOT the saturate() that clamp !)

    SRC:
        - src/OpenColorIO/ops/gradingprimary/GradingPrimaryOpCPU.cpp#L214
        - https://video.stackexchange.com/q/9866

    Args:
        array:
        saturation:
            saturation with different coeff per channel,
            or same value for all channels
        coefs:
            luma coefficient. Default if not specified are BT.709 ones.

    Returns:
        input array with the given saturation value applied
    """

    luma = array * coefs
    luma = numpy.sum(luma, axis=2)
    luma = numpy.stack((luma,) * 3, axis=-1)

    array -= luma
    array *= saturation
    array += luma

    return array


# --------------------------------------------------------------------------------------
# AgX curve function
#
# SRC: https://github.com/sobotka/AgX-S2O3/blob/main/AgX.py
# --------------------------------------------------------------------------------------


agx_compressed_matrix = numpy.asarray(
    [
        [0.84247906, 0.0784336, 0.07922375],
        [0.04232824, 0.87846864, 0.07916613],
        [0.04237565, 0.0784336, 0.87914297],
    ],
    dtype=numpy.float32,
)  # type: numpy.ndarray
"""
SRC: https://github.com/sobotka/AgX-S2O3/blob/main/generate_config.py
"""


def equation_scale(x_pivot, y_pivot, slope_pivot, power):
    # type: (numpy.ndarray, numpy.ndarray, numpy.ndarray, numpy.ndarray) -> numpy.ndarray
    """
    The following is a completely tunable sigmoid function compliments
    of the incredible hard work of Jed Smith. He's an incredible peep,
    but don't let anyone know that I said that.
    """
    a = (slope_pivot * x_pivot) ** -power
    b = ((slope_pivot * (x_pivot / y_pivot)) ** power) - 1.0
    return (a * b) ** (-1.0 / power)


def equation_hyperbolic(x, power):
    # type: (numpy.ndarray, numpy.ndarray) -> numpy.ndarray
    return x / ((1.0 + x**power) ** (1.0 / power))


def equation_term(x, x_pivot, slope_pivot, scale):
    # type: (numpy.ndarray, numpy.ndarray, numpy.ndarray, numpy.ndarray) -> numpy.ndarray
    return (slope_pivot * (x - x_pivot)) / scale


def equation_curve(
    x,  # type: numpy.ndarray
    x_pivot,  # type: numpy.ndarray
    y_pivot,  # type: numpy.ndarray
    slope_pivot,  # type: numpy.ndarray
    power,  # type: numpy.ndarray
    scale,  # type: numpy.ndarray
):
    # type: (...) -> numpy.ndarray
    a = equation_hyperbolic(
        equation_term(x, x_pivot, slope_pivot, scale), power[..., 0]
    )
    a *= scale
    a += y_pivot

    b = equation_hyperbolic(
        equation_term(x, x_pivot, slope_pivot, scale), power[..., 1]
    )
    b *= scale
    b += y_pivot

    curve = numpy.where(scale < 0.0, a, b)
    return curve


def equation_full_curve(lut_array, x_pivot, y_pivot, slope_pivot, power):
    # type: (numpy.ndarray, float, float, float, List[float]) -> numpy.ndarray
    """

    Args:
        lut_array:
        x_pivot:
        y_pivot:
        slope_pivot:
        power:

    Returns:

    """
    lut_size = len(lut_array)

    x_pivot = numpy.tile(numpy.asarray(x_pivot), lut_size)
    y_pivot = numpy.tile(numpy.asarray(y_pivot), lut_size)
    slope_pivot = numpy.tile(numpy.asarray(slope_pivot), lut_size)
    power = numpy.tile(numpy.asarray(power), lut_size)

    scale_x_pivot = numpy.where(lut_array >= x_pivot, 1.0 - x_pivot, x_pivot)
    scale_y_pivot = numpy.where(lut_array >= x_pivot, 1.0 - y_pivot, y_pivot)

    toe_scale = equation_scale(scale_x_pivot, scale_y_pivot, slope_pivot, power[..., 0])
    shoulder_scale = equation_scale(
        scale_x_pivot, scale_y_pivot, slope_pivot, power[..., 1]
    )

    scale = numpy.where(lut_array >= x_pivot, shoulder_scale, -toe_scale)

    return equation_curve(lut_array, x_pivot, y_pivot, slope_pivot, power, scale)


def generateAgxLut(size=4096):
    # type: (int) -> numpy.ndarray
    """
    Ready to encode array for .spi1d LUT.

    Args:
        size: LUT size to generate
    """
    lut_array = numpy.linspace(0.0, 1.0, size)

    AgX_min_EV = -10.0
    AgX_max_EV = +6.5
    AgX_x_pivot = numpy.abs(AgX_min_EV / (AgX_max_EV - AgX_min_EV))
    AgX_y_pivot = 0.50

    general_contrast = 2.0
    limits_contrast = [3.0, 3.25]

    y_LUT = equation_full_curve(
        lut_array,
        AgX_x_pivot,
        AgX_y_pivot,
        general_contrast,
        limits_contrast,
    )
    return y_LUT


def convertOpenDomainToNormalizedLog2(
    in_od,
    minimum_ev=-10.0,
    maximum_ev=+6.5,
    in_midgrey=0.18,
):
    # type: (numpy.ndarray, float, float, float) -> numpy.ndarray
    """
    Similar to OCIO lg2 AllocationTransform.
    SRC: https://github.com/sobotka/AgX-S2O3/blob/main/AgX.py

    Args:
        in_od: floating point image in open-domain state
        minimum_ev:
        maximum_ev:
        in_midgrey:
    """
    in_od[in_od <= 0.0] = numpy.finfo(float).eps
    output_log = numpy.clip(numpy.log2(in_od / in_midgrey), minimum_ev, maximum_ev)
    total_exposure = maximum_ev - minimum_ev

    return (output_log - minimum_ev) / total_exposure


def applyAgxLog(array):
    # type: (numpy.ndarray) -> numpy.ndarray
    """
    Convert open-domain to log domain.

    Returns:
        AgX Log (Kraken) encoded.
    """
    array = array.clip(min=0)
    # matrix/vector multiplication
    array = numpy.einsum("...ij,...j->...i", agx_compressed_matrix, array)
    logarray = convertOpenDomainToNormalizedLog2(
        array,
        minimum_ev=-10.0,
        maximum_ev=6.5,
    )
    logarray = logarray.clip(0.0, 1.0)
    return logarray


def applyAgxLut(array):
    # type: (numpy.ndarray) -> numpy.ndarray
    """
    Convert log data to AgX Base.

    Credits to colour-science python library for implementation.

    Args:
        array: AgX log encoded

    Returns:
        AgX Base encode, ready for display on sRGB monitor.
    """
    lut = generateAgxLut()
    lut_size = len(lut)
    samples = numpy.linspace(0, 1.0, lut_size)

    def interpolate(x):
        # type: (numpy.ndarray) -> numpy.ndarray
        """
        SRC: https://github.com/colour-science/colour/blob/develop/colour/algebra/interpolation.py#L921
        """
        return numpy.interp(x, samples, lut)

    def extrapolate(x):
        # type: (numpy.ndarray) -> numpy.ndarray
        """
        SRC: https://github.com/colour-science/colour/blob/develop/colour/algebra/extrapolation.py#L313
        """
        xi = samples
        yi = lut
        y = numpy.empty_like(x)
        # linear method
        y[x < xi[0]] = yi[0] + (x[x < xi[0]] - xi[0]) * (yi[1] - yi[0]) / (
            xi[1] - xi[0]
        )
        y[x > xi[-1]] = yi[-1] + (x[x > xi[-1]] - xi[-1]) * (yi[-1] - yi[-2]) / (
            xi[-1] - xi[-2]
        )

        in_range = numpy.logical_and(x >= xi[0], x <= xi[-1])
        y[in_range] = interpolate(x[in_range])
        return y

    return extrapolate(array)


def applyLookPunchy(array, punchy_gamma=1.3, punchy_saturation=1.2):
    # type: (numpy.ndarray, float, float) -> numpy.ndarray
    """
    Initally an OCIO CDLTransform.

    SRC: /src/OpenColorIO/ops/cdl/CDLOpCPU.cpp#L348
    "default style is CDL_NO_CLAMP"
    """
    # gamma
    array = cdlPower(array, punchy_gamma)
    array = saturate(array, saturation=punchy_saturation)

    return array


# --------------------------------------------------------------------------------------
# Public
# --------------------------------------------------------------------------------------


def customLook1(array):
    """
    You can perform any grading operation here.
    This is open-domain data encoded in the workspace colorspace.
    """
    return array


def applyAgX(array):
    # type: (numpy.ndarray) -> numpy.ndarray
    """
    -> take linear - sRGB image data as input
    - apply custom grading if any
    - apply the AgX Punchy view-transform
    - return a display-ready array encoded for sRGB SDR monitors

    Args:
        array: float32 array, R-G-B format, sRGB Display
    """

    # Apply Grading
    array = customLook1(array)
    array = applyAgxLog(array)
    array = applyAgxLut(array)  # AgX Base
    array = applyLookPunchy(array=array)
    # Ready for display.
    return array


if __name__ == "__main__":
    # this has external dependencies that you can find on my GitHub but I
    # recommend you to anyway use what you are familiar with for image i-o
    import time
    from pathlib import Path
    import pixelDataTesting
    import lxmImageIO as liio

    source_path = pixelDataTesting.dragonScene.first.path
    print("[__main__] Reading {}".format(source_path))
    image = liio.io.read.readToArray(source_path, method="oiio")

    s_time = time.time()
    new_img = applyAgX(image)
    print("[__main__] image processed in {}s".format(time.time() - s_time))

    target_path = Path("./agx-test.jpg").absolute()
    print("[__main__] Writing image {} to {}".format(new_img.shape, target_path))
    liio.io.write.writeToArray(
        new_img,
        target=target_path,
        bitdepth=numpy.uint8,
        method="oiio",
    )
    print("[__main__] Finished.")
