import dataclasses
import logging

from obs_codegen.c import LUA_IDENT as INDENT
from obs_codegen.generator import BaseGenerator

logger = logging.getLogger(__name__)


@dataclasses.dataclass
class LuaGenerator(BaseGenerator):
    """
    Generate HLSL code as a string following the given input attributes.
    """

    def generateCode(self) -> str:
        """
        Returns:
            valid HLSL code snippet
        """
        str_props = self._generatePropertyList()

        return f"{str_props}"

    def _generatePropertyList(self) -> str:

        out_str = ""

        for colorspace in self.colorspaces_assemblies:

            out_str += INDENT
            out_str += f'obs.obs_property_list_add_int(propOutputColorspace, "{colorspace.name}", {colorspace.id})\n'

        out_str += "\n----------\n"

        for colorspace in self.colorspaces_assemblies:

            out_str += INDENT
            out_str += f'obs.obs_property_list_add_int(propInputColorspace, "{colorspace.name}", {colorspace.id})\n'

        out_str += "\n----------\n"

        for cat in self.cats:

            out_str += INDENT
            out_str += f'obs.obs_property_list_add_int(propCatMethod, "{cat.name}", {cat.id})\n'

        return out_str
