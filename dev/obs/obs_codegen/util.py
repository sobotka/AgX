__all__ = ("slugify",)

import logging
import re

logger = logging.getLogger(__name__)


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
