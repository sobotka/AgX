# Developer documentation

# Introduction.

- `AgX.lua` : direct interface with OBS used for building the GUI
- `AgX.hlsl` : GPU shader with the actual AgX code.
- `colorspace.hlsl` : side-module imported in `AgX.hlsl`

An important point is that part of the code in `colorspace.hlsl` is "procedurally"
generated from python code.

To keep scalability on such a pontentatilly big dataset and reduce human mistakes,
a good part of the code is generated in python.

This can be found in [{root}/dev/obs/obs_codegen](../../dev/obs/obs_codegen)
package. More details below.

# Add a new colorspace.

## Case 1 : gamut/whitepoint/cctf are already there.

You will need :

1. Modify the `/dev/obs/obs_codegen/__main__.py` by adding the new colorspace.
This is done by adding a new instance of `AssemblyColorspace`.

2. Generate the HLSL code by running `__main__` (uncomment the print line if needed)
3. Copy the code generated in `colorspace.hlsl` (using the `//region` `//endregion` comment as marks)
4. Generate the LUA code (uncomment the print line if needed)
5.  Copy the code generated in `AgX.lua` where it "seems" to belong. 
(for now just adding entries to the properties dropdown)

## Case 2 : whole new colorspace

Similar to Case 1 but :

- the step 1. is more complex : you also have to add a new Gamut/TransferFunction/Whitepoint
instance if needed.
- After step 3 you migth need to manually add the corresponding cctf function 
(the name is generated automatically but you have to manually create it)
