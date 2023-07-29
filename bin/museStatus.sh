#! /bin/bash
#
# script to drive the muse command to setup and build Mu2e analysis repos
#

museStatusUsage() {
    cat <<EOF

    muse <global options> status <command options>

    Print information about the Muse working directory and how
    this process is setup.  If "muse setup" has not been run in
    this process, attempt to print some useful information
    assuming the default directory is the Muse working directory.

    <global options>
    -v  : add verbosity

     <command options>
    -h, --help  : print usage


EOF
  return
}


if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    museStatusUsage
    exit 0
fi

[ -n "$MUSE_WORK_DIR"  ] && cd $MUSE_WORK_DIR

FOUND=false
if [ -d build ]; then
    echo ""
    echo "  existing builds:"
    DIRS=$(ls -1 build)
    for DIR in $DIRS; do
        if [ "$DIR" == "$MUSE_STUB" ]; then
            echo  "     $DIR         ** this is your current setup **"
            FOUND=true
        else
            echo  "     $DIR"
        fi

        echo -n "          Build times: "
        if [ -e build/$DIR/.musebuild  ]; then
            cat build/$DIR/.musebuild
        else
            echo "   N/A"
        fi
    done
else
    echo ""
    echo "  no existing builds"
fi

if [[ -n "$MUSE_STUB" && "$FOUND" == "false"  ]]; then
    echo "  presumptive build:"
    echo "     $MUSE_STUB         ** this is your current setup **"
fi
echo ""


[ -z "$MUSE_WORK_DIR" ] && exit 0


[ $MUSE_VERBOSE -gt 0 ] && echo "directory containing repos to be built:"
echo "  MUSE_WORK_DIR = $MUSE_WORK_DIR "
if [ -n "$MUSE_BACKING" ]; then
    for BDIR in $MUSE_BACKING
    do
        echo "    backed by $BDIR"
    done
fi

[ $MUSE_VERBOSE -gt 0 ] && echo "space-separated list of repos in paths:"
echo "  MUSE_REPOS = " $MUSE_REPOS

linkReg="^link/*"
for REPO in $MUSE_REPOS
do
    if [[ "$REPO" =~ $linkReg ]]; then
        REALDIR=$(readlink -f $MUSE_WORK_DIR/$REPO | \
            sed 's|^/cvmfs/mu2e.opensciencegrid.org/||')
        echo "    (deprecated)  $REPO -> $REALDIR"
    fi
done


[ $MUSE_VERBOSE -gt 0 ] && echo "Verbosity, 0 or 1:"
echo "  MUSE_VERBOSE = " $MUSE_VERBOSE
[ $MUSE_VERBOSE -gt 0 ] && echo "user-supplied qualifiers:"
echo "  MUSE_QUALS = " $MUSE_QUALS
[ $MUSE_VERBOSE -gt 0 ] && echo "envset determines the UPS products to use:"
echo "  MUSE_ENVSET = " $MUSE_ENVSET
[ $MUSE_VERBOSE -gt 0 ] && echo "art version number:"
echo "  MUSE_ART = $MUSE_ART ($(echo $SETUP_ART | awk '{print $2}'))"
[ $MUSE_VERBOSE -gt 0 ] && echo "build directory stub based on the build options:"
echo "  MUSE_STUB = " $MUSE_STUB
[ $MUSE_VERBOSE -gt 0 ] && echo "the grid setup file (if any):"
echo "  MUSE_GRID_SETUP = " $MUSE_GRID_SETUP
if [ "$MUSE_PRESOURCE" ]; then
    [ $MUSE_VERBOSE -gt 0 ] && echo "the pre source command:"
    echo "  MUSE_PRESOURCE = " $MUSE_PRESOURCE
fi
if [ "$MUSE_PREBUILD" ]; then
    [ $MUSE_VERBOSE -gt 0 ] && echo "the pre build command:"
    echo "  MUSE_PREBUILD = " $MUSE_PREBUILD
fi

echo

[ $MUSE_VERBOSE -eq 0 ] && exit 0
echo "build options:"
echo "  MUSE_FLAVOR = " $MUSE_FLAVOR
echo "  MUSE_BUILD = " $MUSE_BUILD
echo "  MUSE_COMPILER_E = " $MUSE_COMPILER_E
echo "  MUSE_PYTHON = " $MUSE_PYTHON
echo "  MUSE_G4VIS = " $MUSE_G4VIS
echo "  MUSE_G4ST = " $MUSE_G4ST
echo "  MUSE_G4VG = " $MUSE_G4VG
echo "  MUSE_TRIGGER = " $MUSE_TRIGGER

echo ""
echo "MUSE_ENVSET_DIR = $MUSE_ENVSET_DIR"
echo "MUSE_DIR = $MUSE_DIR"
echo "MUSE_LINK_ORDER = $MUSE_LINK_ORDER"
echo "MU2E_BASE_RELEASE = $MU2E_BASE_RELEASE"
echo ""
echo "MU2E_SEARCH_PATH="
echo $MU2E_SEARCH_PATH | tr ":" "\n"
echo ""
echo "FHICL_FILE_PATH="
echo $FHICL_FILE_PATH | tr ":" "\n"
echo ""
echo "LD_LIBRARY_PATH="
echo $LD_LIBRARY_PATH | tr ":" "\n"
echo ""
echo "PATH="
echo $PATH | tr ":" "\n"
echo ""
echo "ROOT_INCLUDE_PATH="
echo $ROOT_INCLUDE_PATH | tr ":" "\n"

exit 0
