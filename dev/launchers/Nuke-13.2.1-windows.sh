# Nuke launcher script for Windows. To use with GitBash.

# go to repo root assuming cwd is directory of this file
cd ../..
pwd

NUKE_HOME="/C/Program Files/Nuke13.2v1"
NUKE_EXE="$NUKE_HOME/Nuke13.2.exe"

export OCIO="./ocio/config.ocio"

NUKE_SCENE_TEST="./dev/scenes/nuke/AgXc.test_srgb_eotf.nk"

"$NUKE_EXE" $NUKE_SCENE_TEST
