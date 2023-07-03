#! /bin/bash
#
# script to drive the muse command to link a package built
#  in another area to this area so it be used as input to the build
#

usageMuseBacking() {
    cat <<EOF

     muse backing <backing build> <options>

     Create a link to another Muse build area to use it
     as backing build for the local build.  The linked area
     will be included in include, link, fcl and data paths,
     but it will not itself be built.

      Since this command is usually run before "muse setup",
      it must be run in the intended muse working directory

      If the command is run without any arguments, or with -l, a list
      of suggested Offline backing builds will be shown

      <backing build>
           The link selection can be presented various ways
       1) as a path to a muse working directory:
           muse backing /mu2e/app/users/\$USER/myBackingBuild
       2) a branch/commit for a continuous integration backing build:
           muse backing main/c2409d93
       3) the latest commit on the main branch from continuous integration
           muse backing HEAD
       4) a published Offline tag:
           muse backing Offline v09_10_00
               or
           muse backing Offline (the current verison will be used)
       5) any other published Musings and tag:
           muse backing SimJob MDC2020a
               or
           muse backing SimJob (where the current verison will be used)

       Note: A backing link is to a Muse working directory and all the repos
       in that working dir will be available in building and running

       <options>
       -h, --help  : print usage
       -r, --rm  : remove existing link

EOF
  return
}


if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    usageMuseBacking
    exit 0
fi

if [[ "$1" == "-r" || "$1" == "--rm" ]]; then
    rm -f backing
    exit 0
fi

CI_BASE=/cvmfs/mu2e-development.opensciencegrid.org/museCIBuild
MUSINGS=/cvmfs/mu2e.opensciencegrid.org/Musings

TARGET="$1"
VERSION="$2"

#
# if no target, list cvmfs Offline
#

if [[ -z "$TARGET" || "$TARGET" == "-l" ]]; then

    echo "  Recent published Offline releases:"
    CC=$( basename $( readlink -f $MUSINGS/Offline/current ) )
    ls -1 $MUSINGS/Offline | grep -v current | tail -5 | sed "s/$CC/$CC   (current)/"

    echo "  Recent Offline CI builds"
    BRANCHES=$( ls $CI_BASE )
    for BRANCH in $BRANCHES
    do
        find $CI_BASE/$BRANCH -mindepth 1 -maxdepth 1  \
            -printf "%TY-%Tm-%Td %TH:%TM %p\n" |   \
            sort -r | sed 's|'$CI_BASE/'||'
    done

    exit 0
fi

if [ -d link ]; then
    echo "WARNING - a deprecated link directory exists, but will be ignored"
fi

if [ -L backing ]; then
    echo "WARNING - will remove existing backing link:"
    /bin/ls -l backing | awk '{print "    " $NF}'
    /bin/rm backing
elif [ -e backing ]; then
    echo "ERROR - backing already exists and not a link"
    /bin/ls -l backing
    exit 1
fi


#
# try to interpret the target
#

pubreg="^v[0-9,_]*+$"
FTARGET="no_final_target"
NWORD=$(echo $TARGET | awk -F/ '{print NF}')
PRINTCURRENT="no"

if [ $MUSE_VERBOSE -gt 0 ]; then
    echo "TARGET=$TARGET"
    echo "VERSION=$VERSION"
    echo "NWORD=$NWORD"
fi

if [[ "$TARGET" == "HEAD" ||  "$TARGET" == "head" ]]; then
    LASTHASH=$(ls -1tr $CI_BASE/main | tail -1)
    FTARGET=$CI_BASE/main/$LASTHASH
    [ $MUSE_VERBOSE -gt 0 ] &&  \
        echo "backing will be CI build at main/$LASTHASH"

elif [ -d $CI_BASE/$TARGET ]; then
    # NWORD=1 so if X is a Musing, you can still link ./X
    # the target matched a CI build directory
    FTARGET=$CI_BASE/$TARGET
    [ $MUSE_VERBOSE -gt 0 ] && echo "backing will be CI build at $TARGET"

elif [[ -d $MUSINGS/$TARGET && $NWORD -eq 1 ]]; then
    # NWORD=1 so if X is a Musing, you can still link ./X
    # target matched a Musing
    # have to use readlink in case version was "current"
    TV="$VERSION"
    [ -z "$TV" ] && TV="current"
    FTARGET=$( readlink -f $MUSINGS/$TARGET/$TV )
    # readlink will return empty string if dir does not exist
    if [ -z "$FTARGET" ]; then
        echo "ERROR - found target in Musings, but did not match version"
        exit 1
    fi
    [ $MUSE_VERBOSE -gt 0 ] && echo "linking published Musing $TARGET $TV"
    [ "$TV" == "current" ] && PRINTCURRENT="yes"

elif [ -d "$TARGET" ]; then
    # the target is a local directory
    FTARGET=$( readlink -f "$TARGET" )
    [ $MUSE_VERBOSE -gt 0 ] && echo "linking local directory $TARGET"
else
    echo "ERROR - target could not be parsed: $TARGET"
    exit 1
fi

if [ "$PRINTCURRENT" == "yes"  ]; then
    TEMPV=$(echo $FTARGET | awk -F/ '{print $NF}' )
    echo "    $TARGET \"current\" points to $TEMPV"
fi

ln -s $FTARGET backing

if [ -n "$MUSE_WORK_DIR" ]; then
    echo "WARNING - Muse is already setup - changing links changes paths.  "
    echo "          You will need start a new process and run \"muse setup\" again. "
fi

exit 0
