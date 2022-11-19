import itertools
import dataclasses
import logging

import colour
import numpy

from .util import slugify

logger = logging.getLogger(__name__)


@dataclasses.dataclass
class ColorspaceGamut:
    """
    Gamut/Primaries part of a specific colorspace.
    """

    name: str
    matrix_to_XYZ: numpy.ndarray
    matrix_from_XYZ: numpy.ndarray
    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __post_init__(self):
        self.safe_name = slugify(self.name)

    def __hash__(self):
        return hash(self.name)

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


@dataclasses.dataclass
class Whitepoint:
    """
    Whitepoint
    """

    name: str
    coordinates: numpy.ndarray
    """
    CIE xy coordinates as a ndarray(2,)
    """

    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __post_init__(self):
        self.safe_name = slugify(self.name)

    def __hash__(self):
        return hash(self.name)


@dataclasses.dataclass
class Cat:
    """
    Chromatic Adaptation Transform
    """

    name: str
    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __post_init__(self):
        self.safe_name = slugify(self.name)

    def __hash__(self):
        return hash(self.name)


@dataclasses.dataclass
class AssemblyColorspace:
    """
    A custom colorspace used irectly in the target GUI for user slection.
    """

    name: str
    id: int = dataclasses.field(default_factory=itertools.count().__next__, init=False)

    def __post_init__(self):
        self.safe_name = slugify(self.name)

    def __hash__(self):
        return hash(self.name)
