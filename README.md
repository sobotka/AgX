"Fork" of Troy Sobotka's AgX https://github.com/sobotka/AgX

# OCIO

The goal was making the proof-of-concept OCIO config more "production-ready" because, well that's a damn solid concept.

>  **Note**:
>  Compatible with OCIO v2 and OCIO v1.

![agx comparison with aces and filmic](comparison.jpg)

> extreme example rendered with pure ACEScg primaries 

## Changes

- Slight update in the colorspaces names / families 
    - `Generic Data` -> `Passtrough` ( for scalar data)
    - `Linear BT.709` -> `Linear sRGB` (less accurate, but clearer for artists)
    - Appearance view renamed.
- punchy look less punchy (tweak it to your taste anyway)
- Edited display's views :
    - New view `Disabled`, data directly to the display.
    - Removed Golden appearance.
    - Making `Agx Punchy` the default view
- New `ACEScg`, `ACES2065-1` colorspace.
- New `CIE - XYZ -D65`
- **OCIO v1 supports**
    - converted OCIO v2 transforms to v1
    - added allocation vars (not 100% accuracy guarantee)

This was tested on RV, Katana and Nuke but I do not guarantee it is perfectly working on OCIO v1 GPU engine.

## Plans

This config was initially a proof of concept (of an already proof of concept yes) and I planned to write it in Python with OCIO binding but never had the time. But I do not plan any more update in the near future for now.

# Reshade

This repo also include an hlsl implementation for ReShade so you experience AgX in all supported games.

See [hlsl/](hlsl/) directory.

![Stray screenshot with AgX](hlsl/img/stray-3-AgX.jpg)
