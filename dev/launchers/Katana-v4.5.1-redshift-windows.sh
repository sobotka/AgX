# Katana launcher script for Windows. To use with GitBash.

# go to repo root assuming cwd is directory of this file
cd ../..
pwd

KATANA_VERSION="4.5v1"
KATANA_HOME="/C/Program Files/Katana$KATANA_VERSION"

export OCIO="./ocio/config.ocio"

export KATANA_TAGLINE="AgXc DEV - With Redshift."
export DEFAULT_RENDERER=Redshift

export PATH="$PATH:$KATANA_HOME/bin"
export KATANA_CATALOG_RECT_UPDATE_BUFFER_SIZE=1
export KATANA_USER_RESOURCE_DIRECTORY="./dev/prefs/katana"
export KATANA_RESOURCES="$KATANA_USER_RESOURCE_DIRECTORY/resources"

# Redshift config :
REDSHIFT_ROOT="/C/ProgramData/Redshift"
REDSHIFT_KATANA_ROOT="$REDSHIFT_ROOT/Plugins/Katana/$KATANA_VERSION"

export REDSHIFT_CACHE_BUDGET=
export REDSHIFT_CACHE_FOLDER=
export REDSHIFT_SELECTED_CUDA_DEVICES=
export REDSHIFT_COREDATAPATH=$REDSHIFT_ROOT
export REDSHIFT_LOCALDATAPATH=$REDSHIFT_ROOT

export PATH="$PATH:$REDSHIFT_ROOT/bin"
export KATANA_RESOURCES="$KATANA_RESOURCES:$REDSHIFT_KATANA_ROOT"

"$KATANA_HOME\bin\katanaBin.exe"
