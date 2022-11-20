import itertools
import dataclasses
import logging
from typing import Optional

import colour
import numpy

from .util import slugify

logger = logging.getLogger(__name__)


@dataclasses.dataclass
class BaseColorspaceDataclass:

    name: str

    def __post_init__(self):
        self.safe_name = slugify(self.name)


@dataclasses.dataclass
class ColorspaceGamut(BaseColorspaceDataclass):
    """
    Gamut/Primaries part of a specific colorspace.
    """

    matrix_to_XYZ: numpy.ndarray
    matrix_from_XYZ: numpy.ndarray

    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

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

    def __hash__(self):
        return hash(self.name)

    @property
    def id_variable_name(self):
        return f"gamutid_{self.safe_name}"


@dataclasses.dataclass
class Whitepoint(BaseColorspaceDataclass):
    """
    Whitepoint
    """

    coordinates: numpy.ndarray
    """
    CIE xy coordinates as a ndarray(2,)
    """

    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __hash__(self):
        return hash(self.name)

    @property
    def id_variable_name(self):
        return f"whitepointid_{self.safe_name}"


@dataclasses.dataclass
class Cat(BaseColorspaceDataclass):
    """
    Chromatic Adaptation Transform
    """

    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __hash__(self):
        return hash(self.name)

    @property
    def id_variable_name(self):
        return f"catid_{self.safe_name}"


@dataclasses.dataclass
class TransferFunction(BaseColorspaceDataclass):
    """
    Transfer function as decoding and encoding.
    """

    has_encoding: bool = True
    has_decoding: bool = True

    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __hash__(self):
        return hash(self.name)

    @property
    def id_variable_name(self):
        return f"cctf_id_{self.safe_name}"


@dataclasses.dataclass
class AssemblyColorspace(BaseColorspaceDataclass):
    """
    A custom colorspace used irectly in the target GUI for user slection.
    """

    gamut: Optional[ColorspaceGamut]
    whitepoint: Optional[Whitepoint]
    cctf: Optional[TransferFunction]

    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __hash__(self):
        return hash(self.name)

    @property
    def id_variable_name(self):
        return f"colorspaceid_{self.safe_name}"
