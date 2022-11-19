__all__ = ("BaseGenerator",)

import dataclasses
import logging
from abc import abstractmethod

from .entitities import Whitepoint
from .entitities import Cat
from .entitities import AssemblyColorspace
from .entitities import ColorspaceGamut

logger = logging.getLogger(__name__)


@dataclasses.dataclass
class BaseGenerator:
    """
    Generate HLSL code as a string following the given input attributes.
    """

    colorspaces_gamut: list[ColorspaceGamut]
    whitepoints: list[Whitepoint]
    cats: list[Cat]
    colorspaces_assemblies: list[AssemblyColorspace]

    @abstractmethod
    def generateCode(self) -> str:
        """
        Returns:
            valid "standalone" code snippet
        """
        pass
