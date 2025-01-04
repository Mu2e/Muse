#! /bin/bash
#
# script to drive the muse command listing available Muse musing builds
#

museListUsage() {
    cat <<EOF

    muse <global options> list <options> <musing>

    List the most recent versions of available musings,
    and their dependencies.

    <global options>
    -v  : list all versions

    <musing>
        If this is present, only show the versions for this musing

    <options>
    -h, --help  : print usage


    Examples:
    muse list
    muse list Offline

EOF

  return
}


#
# parse args
#


if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    museListUsage
    exit 0
fi

if [[ "$1" == "HEAD" || "$1" == "head" ]]; then
    HMUSINGS=/cvmfs/mu2e-development.opensciencegrid.org/museCIBuild
    for BRANCH in $(ls -1 $HMUSINGS)
    do
        (
            cd $HMUSINGS/$BRANCH
            ls -ltr | awk -v BR=$BRANCH '{ if(NR>1) printf "%3s %2s %5s %s/%s\n", $6, $7, $8, BR, $9  }'
        )
    done
    exit 0
fi

MUSINGS=/cvmfs/mu2e.opensciencegrid.org/Musings

if [ -n "$1" ]; then
    LIST=$1
    if [ ! -d $MUSINGS/$LIST ]; then
        echo "ERROR - could not find musing named $LIST"
        exit 1
    fi
else
    LIST=$(ls $MUSINGS)
fi

for MM in $LIST
do
    echo
    echo ${MM}:

    CURRENTV=$( basename $( readlink -f $MUSINGS/$MM/current ) )

    if [ $MUSE_VERBOSE -gt 0  ]; then
        VLIST=$( ls -1t $MUSINGS/$MM | grep -v current )
    else
        VLIST=$( ls -1t $MUSINGS/$MM | grep -v current | head -3 )
    fi

    for VV in $VLIST
    do
        echo -n "  $VV"
        [ "$VV" == "$CURRENTV" ] && echo -n " (current)"
        echo

        LINKD=$MUSINGS/$MM/$VV/link
        if [ -d $LINKD ]; then
            for LL in $( ls $LINKD )
            do
                FLL=$( readlink -f $LINKD/$LL )
                PKG=$( echo $FLL | awk -F/ '{print $(NF-2)}' )
                VER=$( echo $FLL | awk -F/ '{print $(NF-1)}' )
                echo "    linked (deprecated) to $PKG $VER"
            done
        fi

        BACKD=$MUSINGS/$MM/$VV/backing
        if [ -d $BACKD ]; then
            FLL=$( readlink -f $BACKD )
            echo "    backed by $FLL"
        fi

    done
done

echo

exit 0
