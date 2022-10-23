# AgX.hlsl

AgX implementation for ReShade. *(ReShade is a generic post-processing injector for games and video software)*

# Install

- Install ReShade for your desired game as usual.
- Add the content of the [reshade-shaders/](reshade-shaders/) directory in the `reshade-shaders` directory that you must find next the `game.exe`. (or wherever you specified it should be.)
- In game open ReShader interface and enable `AgX_processing`

# Use

AgX is a DRT (Display Rendering Transform), this means it must comes last in the chain of imagery operations. **So always put it at the bottom of your effect stack so it is applied last.**

## Options

### Input

Options here affect the image before AgX is applied. You can go wild with the values if you like so. AgX will produce pleasing results with nice falloff even in extreme configurations. (that will still look extreme of course)

### Output

Options here affect the image after AgX is applied. This means tweaks here might produce the usual clipping / skews / posterization effect so play with the values softly.

For now the output image is encoded as "sRGB - Display" (with 2.2 power function) (and as it always has been for most game)

## Workflow

- Once AgX enable, I recommend to always increase the `Highlight Gain` to something around 1.0. This will "compensate" for flat highlights that will be produced.
- AgX being a DRT it not meant to provide a creative look to your image (even if the look it give contribute to the creative direction of the image). Nothing prevent you to apply more creative transforms before AgX. Feel free to put some color corrections before. You can try some LUTs too but be aware that some might try to do the same job as AgX and combining them might result in unpleasing visuals. (ex: don't apply an ACES/reinhard/... and other "tonemappers" before AgX.)
- On some game, the default rendering of AgX might not look that good (as explained in Limitations). For example very colourful stylized games. In that case you can retrieve some chroma by boosting first the saturation in the `Input` section. And then in the `Output` section slightly if the result still looks "dull".

# Limitations

1. AgX except "open domain" / "scene-referred" / "high dynamic range" data as input. But ReShade input is "closed-domain" / "display-referred" / "low dynamic range". This can be compensate by increasing the Input Exposure and boosting highlights.

   But there is no magic here, if you have very clamped, destroyed imagery as input, it will still look bad.

2. Even if AgX "improve" color-rendition, it might not still looks better overall. Because the game was designed to look good under a different display-transform and not under AgX. (see [this RDR2 example](img/RDR2-2-AgX.jpg) where the sky looks more flat.)

Also when comparing very fast the "before" and the "after"(with AgX), you might tend to find highlights in the AgX version more flat. Rather than doing quick comparison just try to let your brain/eyes adapt to it for few minutes. Then disable it and compare.

# Comparisons

Check the [img/](img/) directory to find comparison images in different games.

Here is a bunch of interactive before/after :

- Stray : https://imgsli.com/MTMxNDMw
- Lego Bricktales : https://imgsli.com/MTMxNDMx

![lego brick tale comparison image AgX](./img/lego_brick_tale-AgX-tweaked.png) 
![lego brick tale comparison image default](./img/lego_brick_tale-default.png)

# Contributing

This was my first hlsl/reshade shaders so please feel free to open a Pull-Request if you want to improve anything on the code. Especially performances that I totally neglected.
