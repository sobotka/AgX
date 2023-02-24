# go to repo root assuming cwd is directory of this file
cd ../..
pwd

OCIOCHECK="/F/softwares/apps/ocio/apps/ocio_apps/1.0.0/ocio_apps/ociocheck.exe"

export OCIO="./ocio/config.ocio"

"$OCIOCHECK"