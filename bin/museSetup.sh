#! /bin/bash -x
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

           Options may be separated by a space or a colon
 

    Example:
    muse setup  (if in the working directory)
    muse -v setup /mu2e/app/users/$USER/analysis -q debug

EOF

  return
}

if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
    museSetupUsage
    return 0
fi

[ $MUSE_VERBOSE -gt 0 ] && echo "INFO - running museSetup with args: $@"


if [ -n "$MUSE_WORK_DIR" ]; then
    echo "ERROR - Muse already setup for directory "
    echo "               $MUSE_WORK_DIR "
    echo "               with OPTS: $MUSE_OPTS"
    return 1
fi



#
# determine the working dir, and MUSE_WORK_DIR
#

if [[ -n "$1" && "$1" != "-q" ]]; then
    if [  ! -d "$1"  ]; then
	echo "ERROR - could not find Muse directory $1"
	return 1
    fi
    # readlink removes links
    export MUSE_WORK_DIR=$(readlink -f $1)
    
    # remove the target dir from args
    shift

else
    export MUSE_WORK_DIR=$(readlink -f $PWD)
fi

[ $MUSE_VERBOSE -gt 0 ] && \
    echo "INFO - set  MUSE_WORK_DIR=$MUSE_WORK_DIR"

#
# easier to work in the working dir
#

OWD=$PWD
cd $MUSE_WORK_DIR


#
# set the flavor string
#

if ! which ups >& /dev/null ; then
    echo "ERROR - could not find ups command, please setup mu2e"
    return 1
fi

export MUSE_FLAVOR=$( ups flavor | awk -F- '{print $3}' )

#
# parse arguments - everything should be a qualifier
#

# is -q is there, shift it away
[ "$1" == "-q" ] && shift

# if it is of the form a:b, separate the qualifiers
export MUSE_OPTS=$(echo "$@" | sed 's/:/ /g' )

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

for WORD in $MUSE_OPTS
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
    elif [ $WORD == "-q" ]; then
	:
    elif [[ $WORD =~ $ree ]]; then
	export MUSE_ENVSET=$WORD
    else
	echo "ERROR - museSetup could not parse $WORD"
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
# figure out what environmental UPS setups to run
#
# cases allowed so far
# 1) an explicit qualifier like "-q p000"
# 2) Offline is local, pgit or a link, and has a .muse, use recommendation there
# 3) any other local package has a .muse with a recommendation
# 4) $MUSE_WORK_DIR/uNNN exists, take highest number there
# 5) use highest number from $MUSE_ENVSET_DIR
#

if [ -n "$MUSE_ENVSET" ]; then
    # if a set was specified, then do what was requested and done

    if [ $MUSE_VERBOSE -gt 0 ]; then
	echo "INFO - using requested environment $MUSE_ENVSET"
    fi
fi

if [ -z "$MUSE_ENVSET" ]; then
    # look for a local recommendation in a package
    PP=" . "
    [ -d link ] && PP=". ./link"
    DIRS=$( find -L $PP -maxdepth 2 -name .muse | sed -e 's|^\./||' -e 's|/\.muse$||'  |\
      awk '{if($1!="Offline" && $1!="link/Offline") print $0}'  )
    # put these in the front of the search list
    [ -f link/Offline/.muse ] && DIRS="link/Offline $DIRS"
    [ -f Offline/.muse ] && DIRS="Offline $DIRS"

    WARN=false
    for DIR in $DIRS ; do

	WORD=$( cat $DIR/.muse | \
	    awk '{if($1=="ENVSET") print $2}' )
	if [[ -n "$WORD" && -z "$MUSE_ENVSET" ]]; then
	    # take the first in this loop
	    export MUSE_ENVSET=$WORD
	    if [ $MUSE_VERBOSE -gt 0 ]; then 
		echo "INFO - using  environment $MUSE_ENVSET from" 
		echo "           \$MUSE_WORK_DIR/$DIR/.muse"
	    fi
	fi
	[[ -n "$WORD" && -n "$MUSE_ENVSET" && "$WORD" != "$MUSE_ENVSET"  ]] && WARN=true

    done

    if [ "$WARN" == "true" ]; then
	echo "WARNING - local or linked packages have conflicting ENVSET recommendations"
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
    RC=1
fi

if [ -z "$MUSE_BUILD"  ]; then
    echo "ERROR - executing env set did not set build"
    return 1
fi

#
# set the stub for the build path
# this is what allows multiple parallel builds
#

# these are always present
export MUSE_STUB=${MUSE_FLAVOR}-${MUSE_BUILD}-${MUSE_COMPILER_E}-${MUSE_ENVSET}
# TODO leaving this out for now    echo MUSE_PYTHON=$MUSE_PYTHON
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

export MU2E_UPS_QUALIFIERS=+${MUSE_COMPILER_E}:+${MUSE_BUILD}

#
# now set paths for Offline and the build
#

export MU2E_SEARCH_PATH=$MU2E_DATA_PATH


# define link order
# use the local one if it exists
if [ -f $MUSE_WORK_DIR/muse/linkOrder ]; then
    TEMP=$MUSE_WORK_DIR/muse/linkOrder
else
    TEMP=$MUSE_ENVSET_DIR/linkOrder
fi
# end up with a list of words like: Tutorial Offline
export MUSE_LINK_ORDER=$(cat $TEMP | sed 's/#.*$//' )


# list of local muse packages
# buildable packages have a .muse file in the top directory

TEMP_REPOS=$(ls -1 */.muse  2> /dev/null | awk -F/ '{print $1}')
LEMP_REPOS=$(ls -1 link/*/.muse  2> /dev/null | awk -F/ '{print $1"/"$2}')

# test if this is a linked repo
linkReg="^link/*"

#
# the next 35 lines of code orders the repos according
# 1) ABC before link/ABC (Offline takes link precedence over link/Offline)
# 2) the linkOrder
# 3) if the repo is not in the linkOrder, put it first
#

MUSE_REPOS=""
for LREPO in $MUSE_LINK_ORDER
do
    for REPO in $TEMP_REPOS
    do
	if [ "$REPO" == "$LREPO" ]; then
	    export MUSE_REPOS="$MUSE_REPOS $REPO"
	fi
    done
    for REPO in $LEMP_REPOS
    do
	if [ "$REPO" == "link/$LREPO" ]; then
	    export MUSE_REPOS="$MUSE_REPOS $REPO"
	fi
    done
done

TEMP0=""
TEMP1=""
for REPO in $TEMP_REPOS
do
    FOUND=false
    TEST=$( echo $REPO | sed 's/^link//' )
    for LREPO in $MUSE_LINK_ORDER
    do
	[ "$TEST" == "$LREPO"  ] && FOUND=true
    done
    if [ "$FOUND" == "false" ]; then
	if [[ ! "$REPO" =~ $linkReg ]]; then
	    TEMP0="$TEMP0 $REPO"
	else
	    TEMP1="$TEMP1 $REPO"
	fi
    fi
done
export MUSE_REPOS="$TEMP0 $TEMP1 $MUSE_REPOS"


if [ $MUSE_VERBOSE -gt 0 ]; then
    echo "MUSE_LINK_ORDER=$MUSE_LINK_ORDER"
    echo "MUSE_REPOS=$MUSE_REPOS"
fi

# finally done sorting the repos

# reverse the order in order to build prepended path 
MUSE_REPOS_REV=$( echo $MUSE_REPOS | awk '{for(i=1;i<=NF;i++) print $(NF-i+1)," "}' )


#
# set all the paths for the products in the build dir
#
for PP in $MUSE_REPOS_REV
do

    # undo links to get to real path
    # for links, this finds the build area that is on the disk 
    # with that linked area
    #BASE=$(readlink -f  $MUSE_WORK_DIR/$PP/..)
    REPO=$(echo $PP | sed 's/^link\///' )
    BUILD=$MUSE_WORK_DIR/build/$MUSE_STUB/$PP

    if [ $MUSE_VERBOSE -gt 0 ]; then
	echo "Adding repo $PP to paths"
	#echo "     BASE=$BASE"
	echo "     BUILD=$BUILD"
    fi

    # add each package source to SimpleConfig path
    export MU2E_SEARCH_PATH=`dropit -p $MU2E_SEARCH_PATH -sfe $MUSE_WORK_DIR/$PP`
    # add each package source
    export FHICL_FILE_PATH=`dropit -p $FHICL_FILE_PATH -sfe $MUSE_WORK_DIR/$PP`

    # add package generated fcl 
    if [[ "$REPO" == "Offline" ]]; then
	# assuming only Offline generates fcl
 	export FHICL_FILE_PATH=`dropit -p $FHICL_FILE_PATH -sfe $BUILD`
    fi
    # libraries built in each package
    export LD_LIBRARY_PATH=`dropit -p $LD_LIBRARY_PATH -sfe $BUILD/lib`
    export CET_PLUGIN_PATH=`dropit -p $CET_PLUGIN_PATH -sfe $BUILD/lib`
    # bins build in each package
    export PATH=`dropit -p $PATH -sfe $BUILD/bin`
    # where root finds includes
    export ROOT_INCLUDE_PATH=`dropit -p $ROOT_INCLUDE_PATH -sfe $MUSE_WORK_DIR/$PP`
    
    PATHS=$(cat $PP/.muse |  \
	awk '{if($1=="PYTHONPATH") print $2}')
    for PA in $PATHS
    do
	export PYTHONPATH=`dropit -p $PYTHONPATH -sf $MUSE_WORK_DIR/$PP/$PA`
    done
    
    PATHS=$(cat $PP/.muse | \
	awk '{if($1=="PATH") print $2}')
    for PA in $PATHS
    do
	export PATH=`dropit -p $PATH -sf $MUSE_WORK_DIR/$PP/$PA`
    done
    
    PATHS=$(cat $PP/.muse | \
	awk '{if($1=="FHICL_FILE_PATH") print $2}')
    for PA in $PATHS
    do
	export FHICL_FILE_PATH=`dropit -p $FHICL_FILE_PATH -sf $MUSE_WORK_DIR/$PP/$PA`
    done
    

#    if [ "$PP" == "Offline" ]; then
#	export MU2E_BASE_RELEASE=$BASE/Offline
#    fi

done

#
# set paths that start in the MUSE_WORK_DIR
# and can be referred as Offline/JobConfig... or build/...
# when the include files are shifted, these will be the only ones necessary
#
if [ -d link ]; then
    export MU2E_SEARCH_PATH=`dropit -p $MU2E_SEARCH_PATH -sfe $MUSE_WORK_DIR/link` 
    export FHICL_FILE_PATH=`dropit -p $FHICL_FILE_PATH -sfe $MUSE_WORK_DIR/link`
    export ROOT_INCLUDE_PATH=`dropit -p $ROOT_INCLUDE_PATH -sfe $MUSE_WORK_DIR/link`
fi
export MU2E_SEARCH_PATH=`dropit -p $MU2E_SEARCH_PATH -sfe $MUSE_WORK_DIR`
export FHICL_FILE_PATH=`dropit -p $FHICL_FILE_PATH -sfe $MUSE_WORK_DIR`
    export ROOT_INCLUDE_PATH=`dropit -p $ROOT_INCLUDE_PATH -sfe $MUSE_WORK_DIR`

#
# "setup" the linked packages by making sure links exist
# from our build area to the linked build area
#
if [ -d link ]; then
    mkdir -p $MUSE_BUILD_BASE/link
    for REPO in $( ls  link )
    do
	BASE=$( readlink -f  link/$REPO/.. )
	if [ ! -d  $MUSE_BUILD_BASE/link/$REPO  ]; then
	    if [ -d  $BASE/$MUSE_BUILD_BASE/$REPO ]; then
		ln -s $BASE/$MUSE_BUILD_BASE/$REPO $MUSE_BUILD_BASE/link/$REPO  
	    else
		echo "WARNING - linked repo $REPO does not have the $MUSE_STUB build"
	    fi
	fi
    done
fi


if [ $RC -ne 0  ]; then
    echo "ERROR - setup did not run correctly"
    return 1
fi

echo "     Build: $MUSE_BUILD     Core: $MUSE_FLAVOR $MUSE_COMPILER_E $MUSE_ENVSET     Options: $MUSE_OPTS"

return 0
