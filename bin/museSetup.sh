#! /bin/bash
#
# script to drive the muse command to setup and build Mu2e analysis repos
#

museSetupUsage() {
    cat <<EOF

    muse <global options> setup <directory>  <options>

    <global options>
    -v  : add verbosity

    <directory>
        If this is present, and is a directory path, then this will be
        set as the Muse working directory.  If not present, then
        the default directory is used as the Muse working directory.
        Some Muse builds are published on cvmfs (Musings), and you can setup
        Muse to point to those areas.

    <options>
    -h, --help  : print usage
    -q  :  add the following build qualifiers
            prof/debug  - complier switches (default prof)
            eNN - compiler, like "e20" (default by an algorithm)
            pNNN/uNNN - environmental set, like "p020" (default by an algorithm)
                 the following default to off:
            ogl - link geant OGL graphics lib (default off)
            qt - switch to geant libraries with qt graphics (default off)
            st - compile with multi-threading flag off
            trigger - build only libraries needed in the trigger

           Multiple qualifiers should be separated by a colon


    Examples:
    muse setup  (if default directory is the Muse working directory)
    muse -v setup /mu2e/app/users/$USER/analysis -q debug

    Musings examples:
    muse setup Offline  (setup the current publishd Offline tag)
    muse setup Offline v10_00_00  (setup this version of Offline)
    muse setup SimJob  (setup current version of SimJob - Offline and Production)
    muse setup HEAD    (setup latest CI build)


EOF

  return
}

#
# print error messages, cleanup from a early error if possible
#
errorMessageBad() {
    echo "        The environment may be broken, please try again in a new shell"
    export MUSE_ERROR="yes"
}
errorMessage() {
    local WORDS=$( printenv | tr "=" " " | awk '{if(index($1,"MUSE_")==1) print $1}')
    for WORD in $WORDS
    do
        if [[ "$WORD" != "MUSE_DIR" && "$WORD" != "MUSE_ENVSET_DIR" ]]; then
            unset $WORD
        fi
    done
    echo "        The environment is clean, try again in this shell"
}

# dropit doesn't do the right thing if current path is empty
# $1=existing path, $2=new path to be added
# return new full path
mdropit() {
    if [ -z "$2" ]; then # existing path was blank
        echo $1
    else
        echo $(dropit -p $1 -sfe $2)
    fi
}

[ $MUSE_VERBOSE -gt 0 ] && echo "INFO - running museSetup with args: $@"

if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    museSetupUsage
    return 0
fi

if [ -n "$MUSE_ERROR" ]; then
    echo "ERROR - Muse setup was incomplete "
    errorMessageBad
    return 1
fi

if [ -n "$MUSE_WORK_DIR" ]; then
    echo "ERROR - Muse already setup for directory "
    echo "               $MUSE_WORK_DIR "
    echo "               with OPTS: $MUSE_QUALS"
    return 1
fi

#
# parse args
#

MUSE_QUALS=""

ARG1=""
ARG2=""
QFOUND=""
for ARG in "$@"
do
    if [ "$QFOUND" == "true" ]; then
        MUSE_QUALS="$MUSE_QUALS $ARG"
    elif [ "$ARG" == "-q" ]; then
        QFOUND="true"
    elif [[  "$ARG" == "-h" || "$ARG" == "--help" || "$ARG" == "help" ]]; then
        museSetupUsage
        return 0
    else
        if [ "$ARG1" == "" ]; then
            ARG1="$ARG"
        elif [ "$ARG2" == "" ]; then
            ARG2="$ARG"
        else
            echo "ERROR - too many unqualified arguments"
            errorMessage
            return 1
        fi
    fi
done


#
# determine the working dir, and MUSE_WORK_DIR
#

if [ -z "$ARG1" ]; then
    # if no args, then assume the local dir is the Muse working dir
    export MUSE_WORK_DIR=$( readlink -f $PWD)
else
    MUSINGS=/cvmfs/mu2e.opensciencegrid.org/Musings
    CI_BASE=/cvmfs/mu2e-development.opensciencegrid.org/museCIBuild
    if [[  -d "$ARG1"  && ! -d $ARG1/.git ]]; then
        # if the first arg is a directory, accept that as Muse working dir
        # readlink removes links
        export MUSE_WORK_DIR=$( readlink -f $ARG1)
    elif [  -d "$MUSINGS/$ARG1"  ]; then
        # second choice, if the first arg is a Musings dir
        if [  -n "$ARG2"  ]; then
            # try to interpret arg2 as a Musings version number
            if [ -d "$MUSINGS/$ARG1/$ARG2" ]; then
                export MUSE_WORK_DIR=$( readlink -f $MUSINGS/$ARG1/$ARG2 )
            fi
        else
            # no Musings version, look for a current
            if [  -d "$MUSINGS/$ARG1/current" ]; then
                export MUSE_WORK_DIR=$( readlink -f $MUSINGS/$ARG1/current )
            fi
        fi
    elif [[  "$ARG1" == "HEAD" || "$ARG1" == "head" ]]; then
        # take the latest main CI
        HASH=$(/bin/ls -1tr $CI_BASE/main | tail -1)
        export MUSE_WORK_DIR=$( readlink -f $CI_BASE/main/$HASH )
    elif [ -d $CI_BASE/$ARG1 ]; then
        # use the requested CI build
        export MUSE_WORK_DIR=$( readlink -f $CI_BASE/$ARG1 )
    fi
    if [ -z "$MUSE_WORK_DIR" ]; then
        echo "ERROR - could not find/interpret directory arguments: $ARG1 $ARG2"
        errorMessage
        return 1
    fi

fi

[ $MUSE_VERBOSE -gt 0 ] && \
    echo "INFO - set  MUSE_WORK_DIR=$MUSE_WORK_DIR"

#
# easier to work in the working dir
#

OWD=$PWD
cd $MUSE_WORK_DIR

#
# if there is a .git in the working dir, stop, since, almost 100% certain,
# the user is trying to setup in Offline dir
#
if [ -d .git ] ; then
    echo "ERROR - \$MUSE_WORK_DIR contains .git.  Are you trying to setup inside of"
    echo "        Offline or other repo instead of the directory which contains them?"
    errorMessage
    return 1
fi

if [ -d link ]; then
    echo "WARNING - a deprecated link directory exists, but will be ignored"
fi

#
# set the flavor string
#

if ! which ups >& /dev/null ; then
    echo "ERROR - could not find ups command, please setup mu2e"
    errorMessage
    return 1
fi

export MUSE_FLAVOR=$( ups flavor | awk -F- '{print $3}' )
if [ -z "$MUSE_FLAVOR" ]; then
    echo "ERROR - could not run ups flavor, you might need to set UPS_OVERRIDE"
    errorMessage
    return 1
fi

#
# parse arguments - everything should be a qualifier
#

# if it is of the form a:b, separate the qualifiers
export MUSE_QUALS=$(echo "$MUSE_QUALS" | sed 's/:/ /g' )

# defaults
export MUSE_BUILD=""
export MUSE_COMPILER_E=""
export MUSE_PYTHON=""
export MUSE_G4VIS=""
export MUSE_G4ST=""
export MUSE_G4VG=""
export MUSE_TRIGGER=""
export MUSE_ENVSET=""

#
# now parse the words
#

# regex for compiler strings like e19 or e20
rec="^[e][0-9]{2}$"
# regex for version strings like p011 or u000
ree="^[pu][0-9]{3}$"

for WORD in $MUSE_QUALS
do
    if [ $WORD == "prof" ]; then
        export MUSE_BUILD=prof
    elif [ $WORD == "debug" ]; then
        export MUSE_BUILD=debug
    elif [[ $WORD =~ $rec ]]; then
        export MUSE_COMPILER_E=$WORD
    elif [ $WORD == "ogl" ]; then
        export MUSE_G4VIS=ogl
    elif [ $WORD == "qt" ]; then
        export MUSE_G4VIS=qt
    elif [ $WORD == "st" ]; then
        export MUSE_G4ST=st
    elif [ $WORD == "trigger" ]; then
        export MUSE_TRIGGER=trigger
    elif [[ $WORD =~ $ree ]]; then
        export MUSE_ENVSET=$WORD
    else
        echo "ERROR - museSetup could not parse $WORD"
        errorMessage
        return 1
    fi
done


if [ $MUSE_VERBOSE -gt 0 ]; then
    echo "Parsed qualifiers:"
    echo MUSE_FLAVOR=$MUSE_FLAVOR
    echo MUSE_BUILD=$MUSE_BUILD
    echo MUSE_COMPILER_E=$MUSE_COMPILER_E
    echo MUSE_PYTHON=$MUSE_PYTHON
    echo MUSE_G4VIS=$MUSE_G4VIS
    echo MUSE_G4ST=$MUSE_G4ST
    echo MUSE_G4VG=$MUSE_G4VG
    echo MUSE_TRIGGER=$MUSE_TRIGGER
fi

#
# build the chain of backing builds
#
export MUSE_BACKING=""
MUSE_BACKING_REV=""
QMORE="true"
CURRDIR="$MUSE_WORK_DIR"
while [ "$QMORE" ]
do
  if [ -e $CURRDIR/backing ]; then
      CURRDIR=$(readlink -f $CURRDIR/backing )
      MUSE_BACKING="$MUSE_BACKING $CURRDIR"
      MUSE_BACKING_REV="$CURRDIR $MUSE_BACKING_REV"
  else
      QMORE=""
  fi
done

if [ $MUSE_VERBOSE -gt 0 ]; then
    echo "INFO - detected backing builds:"
    for DD in $MUSE_BACKING
    do
        echo "    $DD"
    done
fi


#
# figure out what environmental UPS setups to run
#
# cases allowed
# 1) an explicit qualifier like "-q p000"
# 2) the MUSE_WORK_DIR has a .muse
# 3) Offline is local, mgit or a backing build, and has a .muse
# 4) any other local package has a .muse with a recommendation
# 5) $MUSE_WORK_DIR/muse/uNNN exists, take highest number there
# 6) use highest number from $MUSE_ENVSET_DIR
#

if [ -n "$MUSE_ENVSET" ]; then
    # if a set was specified, then do what was requested and done

    if [ $MUSE_VERBOSE -gt 0 ]; then
        echo "INFO - using requested environment $MUSE_ENVSET"
    fi
fi

if [ -z "$MUSE_ENVSET" ]; then
    # look for a local recommendation in a package, not Offline
    DIRS0=$( /bin/ls -1 */.muse 2> /dev/null  | \
        sed 's|/\.muse$||'  | \
        awk '{if($1!="Offline") print $0}'  | \
        tr "\n" " " )

    # look for an Offline in a backing build
    DIRS1=""
    for DD in $MUSE_BACKING # deeper in the chain is less favored
    do
        if [ -e "$DD/Offline/.muse" ]; then
            DIRS1="$DD/Offline $DIRS1"
        fi
    done
    DIRS="$DIRS0 $DIRS1"

    # put these in the front of the search list
    [ -f Offline/.muse ] && DIRS="Offline $DIRS"
    [ -f ./.muse ] && DIRS=". $DIRS"

    WARN=false
    for DIR in $DIRS ; do

        WORD=$( cat $DIR/.muse | \
            awk '{if($1=="ENVSET") print $2}' )
        if [[ -n "$WORD" && -z "$MUSE_ENVSET" ]]; then
            # take the first in this loop
            export MUSE_ENVSET=$WORD
            if [ $MUSE_VERBOSE -gt 0 ]; then
                echo "INFO - using  environment $MUSE_ENVSET from"
                echo "           ${DIR}/.muse"
            fi
        fi
        [[ -n "$WORD" && -n "$MUSE_ENVSET" && "$WORD" != "$MUSE_ENVSET"  ]] && WARN=true

    done

    if [ "$WARN" == "true" ]; then
        echo "WARNING - local packages or backing Offline have conflicting ENVSET recommendations"
        echo "                 in .muse files.  Using $MUSE_ENVSET selected by search algorithm."
    fi

fi

if [[ -z "$MUSE_ENVSET" && -d $MUSE_WORK_DIR/muse ]]; then

    # take the latest from the env sets in the user area
    WORD=$( find $MUSE_WORK_DIR/muse -maxdepth 1  -type f  -regex ".*u[0-9]..$" -printf "%f\n" | sort | tail -1 )
    if [ -n "$WORD" ]; then
        export MUSE_ENVSET=$WORD
        if [ $MUSE_VERBOSE -gt 0 ]; then
            echo "INFO - using  environment $MUSE_ENVSET from"
            echo "           $MUSE_WORK_DIR"
        fi
    fi

fi

if [ -z "$MUSE_ENVSET" ]; then
    # if still missing, go to permanent repo of environmental sets
    WORD=$( find $MUSE_ENVSET_DIR -maxdepth 1  -type f  -regex '.*p[0-9]..$' -printf "%f\n" | sort | tail -1 )
    if [ -n "$WORD" ]; then
        export MUSE_ENVSET=$WORD
        if [ $MUSE_VERBOSE -gt 0 ]; then
            echo "INFO - using  environment $MUSE_ENVSET from"
            echo "           $MUSE_ENVSET_DIR"
        fi
    fi
fi

if [ -z "$MUSE_ENVSET"  ]; then
    echo "ERROR - did not find any env set"
    errorMessage
    return 1
fi


if [ $MUSE_VERBOSE -gt 0 ]; then
    echo "INFO - running environmental set $MUSE_ENVSET "
fi

if [ -r $MUSE_WORK_DIR/muse/$MUSE_ENVSET ]; then
    source $MUSE_WORK_DIR/muse/$MUSE_ENVSET
    RC=$?
elif [ -r $MUSE_ENVSET_DIR/$MUSE_ENVSET ]; then
    source $MUSE_ENVSET_DIR/$MUSE_ENVSET
    RC=$?
else
    echo "ERROR - did not find env set $MUSE_ENVSET"
    # regex for version strings like u000
    reu="^u[0-9]{3}$"
    if [[ "$MUSE_ENVSET" =~ $reu ]]; then
        echo "        local env sets of the form uNNN should be placed in \$MUSE_WORK_DIR/muse"
    fi
    errorMessage
    return 1
fi

if [[ -z "$MUSE_BUILD"  || $RC -ne 0 ]]; then
    echo "ERROR - env set did not execute correctly"
    errorMessageBad
    return 1
fi

#
# set the stub for the build path
# this is what allows multiple parallel builds
#

# these are always present
export MUSE_STUB=${MUSE_FLAVOR}-${MUSE_BUILD}-${MUSE_COMPILER_E}-${MUSE_ENVSET}
# leaving this out for now    echo MUSE_PYTHON=$MUSE_PYTHON
[ -n "$MUSE_G4VIS" ]   && export MUSE_STUB=${MUSE_STUB}-$MUSE_G4VIS
[ -n "$MUSE_G4ST" ]    && export MUSE_STUB=${MUSE_STUB}-$MUSE_G4ST
[ -n "$MUSE_G4VG" ]    && export MUSE_STUB=${MUSE_STUB}-$MUSE_G4VG
[ -n "$MUSE_TRIGGER" ] && export MUSE_STUB=${MUSE_STUB}-$MUSE_TRIGGER

export MUSE_BUILD_BASE=build/$MUSE_STUB
export MUSE_BUILD_DIR=$MUSE_WORK_DIR/$MUSE_BUILD_BASE

if [ $MUSE_VERBOSE -gt 0 ]; then
    echo MUSE_STUB=$MUSE_STUB
    echo MUSE_BUILD_DIR=$MUSE_BUILD_DIR
fi

# this is needed for mu2etools setup
export MU2E_UPS_QUALIFIERS=+${MUSE_COMPILER_E}:+${MUSE_BUILD}

#
# check that the backing builds have the same build as we need
#
for BDIR in $MUSE_BACKING
do
    if [ ! -d $BDIR/build/$MUSE_STUB ]; then
        echo "ERROR - backing build area missing required build ($MUSE_STUB)"
        echo "        $BDIR"
        errorMessageBad
        return 1
    fi
done

#
# set paths for builds
#

export MU2E_SEARCH_PATH=$MU2E_DATA_PATH

# define link order
# use the local one if it exists
if [ -f $MUSE_WORK_DIR/muse/linkOrder ]; then
    TEMP=$MUSE_WORK_DIR/muse/linkOrder
    echo "INFO - using link order from muse/linkOrder"
else
    TEMP=$MUSE_ENVSET_DIR/linkOrder
fi
# end up with a list of words like: Tutorial Offline
export MUSE_LINK_ORDER=$(cat $TEMP | sed 's/#.*$//' | tr "\n\t" "  " | tr -s " " )


#
# start from the furthest build area, then step thru backing builds
# in reverse order up to the local dir.
# For each dir, find repos, sort them in link order, and add to
# the front of the link path
#
MUSE_REPOS=""
MUSE_LOCAL_REPOS=""

for BDIR in $MUSE_BACKING_REV $MUSE_WORK_DIR
do

    # add the paths that point to the build areas
    if [ $MUSE_VERBOSE -gt 0 ]; then
        echo "Adding build area paths for $BDIR"
    fi
    export MU2E_SEARCH_PATH=$( mdropit $MU2E_SEARCH_PATH $BDIR )
    export FHICL_FILE_PATH=$( mdropit $FHICL_FILE_PATH $BDIR )
    export ROOT_INCLUDE_PATH=$( mdropit $ROOT_INCLUDE_PATH $BDIR )

    # then add the paths that depend on the indivdual repos

    # list of muse packages in this build area
    # buildable packages have a .muse file in the top directory

    TEMP_REPOS=$(/bin/ls -1 $BDIR/*/.muse  2> /dev/null | awk -F/ '{printf "%s ", $(NF-1)}' )

    #
    # the next 20 lines of code orders the repos according
    # 1) the linkOrder
    # 3) if the repo is not in the linkOrder, put it first
    #

    MUSE_REPOS_BDIR=""

    # order known repos
    TEMP1=""
    for LREPO in $MUSE_LINK_ORDER
    do
        for REPO in $TEMP_REPOS
        do
            [ "$REPO" == "$LREPO"  ] && TEMP1="${TEMP1}$REPO "
        done
    done

    # add unknown repos to front of link order
    TEMP0=""
    for REPO in $TEMP_REPOS
    do
        QFOUND=""
        for LREPO in $MUSE_LINK_ORDER
        do
            [ "$REPO" == "$LREPO"  ] && QFOUND="true"
        done
        [ ! "$QFOUND" ] && TEMP0="${TEMP0}$REPO "
    done

    # the repos in this dir
    MUSE_REPOS_BDIR="$TEMP0 $TEMP1"
    # all repos
    export MUSE_REPOS="${MUSE_REPOS_BDIR} $MUSE_REPOS"
    [ "$BDIR" == "$MUSE_WORK_DIR" ] && export MUSE_LOCAL_REPOS="$MUSE_REPOS_BDIR"

    # done sorting the repos

    # reverse the order in order to build prepended path
    MUSE_REPOS_BDIR_REV=$( echo $MUSE_REPOS_BDIR | awk '{for(i=1;i<=NF;i++) print $(NF-i+1)," "}' )


    #
    # set all the paths for the products in the build dir
    #
    for REPO in $MUSE_REPOS_BDIR_REV
    do

        RDIR=$BDIR/$REPO
        BUILD=$BDIR/build/$MUSE_STUB/$REPO

        if [ $MUSE_VERBOSE -gt 0 ]; then
            echo "Adding repo path $BUILD"
        fi

        # add package-generated fcl (trigger) and data (gdml) paths
        # assuming only Offline generates these
        if [ "$REPO" == "Offline" ]; then
            TEMP=$BDIR/build/$MUSE_STUB
            export FHICL_FILE_PATH=$( mdropit  $FHICL_FILE_PATH $TEMP )
            export MU2E_SEARCH_PATH=$( mdropit $MU2E_SEARCH_PATH $TEMP )
        fi

        # libraries built in each package
        export LD_LIBRARY_PATH=$( mdropit $LD_LIBRARY_PATH $BUILD/lib )
        export CET_PLUGIN_PATH=$( mdropit $CET_PLUGIN_PATH $BUILD/lib )

        # bins built in each package
        export PATH=$( mdropit $PATH $BUILD/bin )

        # python wrappers built in each package
        export PYTHONPATH=$( mdropit $PYTHONPATH $BUILD/pywrap )

        # if the package has a python subdir, or bin area, then
        # include that in the paths, as requested in .muse
        PATHS=$(cat $RDIR/.muse |  \
            awk '{if($1=="PYTHONPATH") print $2}')
        for PA in $PATHS
        do
            export PYTHONPATH=$( mdropit $PYTHONPATH $RDIR/$PA )
        done

        PATHS=$(cat $RDIR/.muse | \
            awk '{if($1=="PATH") print $2}')
        for PA in $PATHS
        do
            export PATH=$( mdropit $PATH $RDIR/$PA )
        done

        PATHS=$(cat $RDIR/.muse | \
            awk '{if($1=="FHICL_FILE_PATH") print $2}')
        for PA in $PATHS
        do
            export FHICL_FILE_PATH=$( mdropit $FHICL_FILE_PATH $RDIR/$PA )
        done

    done  # loop over repos in a build area


done   # big loop over backing build dirs

# clean whitespace
export MUSE_LINK_ORDER=$(echo $MUSE_LINK_ORDER)
export MUSE_REPOS=$(echo $MUSE_REPOS)

if [ $MUSE_VERBOSE -gt 0 ]; then
    echo "MUSE_LINK_ORDER=$MUSE_LINK_ORDER"
    echo "MUSE_REPOS=$MUSE_REPOS"
fi

#
# the next 30 lines checks if there were backing repos out of order,
# for example, if you have Offline locally, then you might have the
# backing chain:  Offline -> TrkAna -> Offline
# this has chance of inconsistent builds and memory errors because
# TrkAna will see libraries from the first Offline,
# but expect them from the second
#

QWARN=""
NR=$(echo $MUSE_REPOS | wc -w)
RARR=($MUSE_REPOS)
# loop over all repos
for IRU in ${!RARR[@]}
do
    RU=${RARR[$IRU]}
    # loop over all downstream repos
    IRD=$(($IRU+1))
    while [ $IRD -lt $NR ]
    do
        RD=${RARR[$IRD]}
        QFU=""
        QFD=""
        # check where they are in the link order
        for RR in $MUSE_LINK_ORDER
        do
            if [ "$RU" == "$RR" ]; then
                QFU="found"
                # while in linkOrder loop, found upstream
                # after downstream, which is wrong order
                if [ "$QFD" ]; then
                    QWARN="yes"
                    if [ $MUSE_VERBOSE -gt 0 ]; then
                        echo "Repo order check found $RU ahead of $RD"
                    fi
                fi
            fi
            [ "$RD" == "$RR" ] && QFD="found"
        done
        IRD=$(($IRD+1))
    done
done

if [ "$QWARN" ]; then
    echo "Warning - found repos in an unexpected link order,"
    echo "     such as Offline upstream of TrkAna.  This can lead to "
    echo "     inconsistent builds and memory errors."
fi

#
# check if we setup an empty directory, if so give a warning
#
if [[ -z "$MUSE_REPOS" && -z "$MUSE_BACKING" ]]; then
    echo
    echo "Note: your working dir has no buildable or linked repos."
    echo "This is allowed, but also might indicate a mistake.."
    echo
fi


#
# if build area is on cvmfs and contains a setup.sh script, typically written
# by the tarball command, then set the grid convenience environmental
#
cvmfsReg="^/cvmfs/*"
if [[ "$MUSE_BUILD_DIR" =~ $cvmfsReg ]]; then
    if [ -f $MUSE_BUILD_DIR/setup.sh ] ; then
        export MUSE_GRID_SETUP=$MUSE_BUILD_DIR/setup.sh
    fi
fi


echo "     Build: $MUSE_BUILD     Core: $MUSE_FLAVOR $MUSE_COMPILER_E $MUSE_ENVSET     Options: $MUSE_QUALS"


#
# add the pre-commit hook to check for whitespace errors, if possible
#

if git -C Offline config --local core.whitespace  \
                     trailing-space,tab-in-indent >& /dev/null ; then

    LOCALHOOK=$MUSE_WORK_DIR/Offline/.git/hooks/pre-commit
    STDHOOK=$MUSE_ENVSET_DIR/pre-commit

    if [ ! -e $LOCALHOOK ]; then
        cp $STDHOOK $LOCALHOOK
    elif ! diff $STDHOOK $LOCALHOOK >& /dev/null ; then
        echo "Local Offline git pre-commit hook is different than the current Muse version."
        echo "To update to the latest version and stop this warning:"
        echo "cp $STDHOOK $LOCALHOOK"
    fi

fi


return 0
