__all__ = (
    "convert3x3MatrixToHlslStr",
    "generateCommentHeader",
)

import logging
from typing import Optional

import numpy

from obs_codegen.c import ROUND_THRESHOLD
from obs_codegen.c import HLSL_INDENT as INDENT

logger = logging.getLogger(__name__)


def convert3x3MatrixToHlslStr(
    matrix: numpy.ndarray, escape_end_of_line: bool = False
) -> str:
    """
    To use with the #define macro

    Args:
        escape_end_of_line: True to add a ``//`` before each lien break.
        matrix: 3x3 matrix as numpy array

    Returns:
        partial HLSL variable declaration.
    """
    linebreak = "\\\n" if escape_end_of_line else "\n"

    return (
        f"{linebreak}"
        f"{INDENT}{round(matrix[0][0], ROUND_THRESHOLD)}, {round(matrix[0][1], ROUND_THRESHOLD)}, {round(matrix[0][2], ROUND_THRESHOLD)},{linebreak}"
        f"{INDENT}{round(matrix[1][0], ROUND_THRESHOLD)}, {round(matrix[1][1], ROUND_THRESHOLD)}, {round(matrix[1][2], ROUND_THRESHOLD)},{linebreak}"
        f"{INDENT}{round(matrix[2][0], ROUND_THRESHOLD)}, {round(matrix[2][1], ROUND_THRESHOLD)}, {round(matrix[2][2], ROUND_THRESHOLD)}{linebreak}"
    )


def generateCommentHeader(title: str, description: Optional[str] = None) -> str:
    """
    Generate an HLSL comment block to summarize the code that can be found under.
    Example::
        /* ------...
        title

        description
        -------...*/
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
