# Katana launcher script for Windows. To use with GitBash.

# go to repo root assuming cwd is directory of this file
cd ../..
pwd

C4D_HOME="/C/Program Files/Maxon Cinema 4D 2023"

export OCIO="$PWD/ocio/config.ocio"
#export OCIO="$PWD/ocio/rs-minimal-2.ocio"
#export OCIO="/F/softwares/color/library/misc/substance/original/config.ocio"
#export OCIO="/C/ProgramData/Redshift/Data/OCIO/config.ocio"
#export OCIO="$PWD/ocio/rs-official-stripped.ocio"
echo $OCIO

"$C4D_HOME/Cinema 4D.exe"
