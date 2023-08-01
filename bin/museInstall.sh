#
# script to copy a Muse repo into a UPS product directory
# and make a UPS tarball
# will not force the new version to be the "current" version
#
#
# Two arguments required:
# $1  version, like v1_0_0
# $2 the path to the products area to install it
#

if [ $# -ne 2 ]; then
    echo "ERROR expected two arguments"
    echo " version path/to/products"
    exit 1
fi

VERSION=$1
PDIR=$2


if [ ! -d $PDIR ]; then
    echo "ERROR - products dir does not exist"
    exit 1
fi

OWD=$PWD
SDIR=$(dirname $(readlink -f $BASH_SOURCE)  | sed 's|/bin||' )

cd $PDIR
mkdir -p muse
cd muse
mkdir -p $VERSION
cd $VERSION

rsync --exclude "*~" --exclude "*__*"  --exclude "museInstall.sh" \
    -r $SDIR/bin $SDIR/python  $SDIR/config .
mkdir -p ups
cd ups

cat > muse.table <<EOL
File    = table
Product = muse

Group:

FLAVOR = NULL
QUALIFIERS = ""

  Common:
    Action = setup
      prodDir()
      setupEnv()
      envSet(\${UPS_PROD_NAME_UC}_VERSION, $VERSION)

      envPrepend(PATH, \${\${UPS_PROD_NAME_UC}_DIR}/bin)
      envPrepend(PYTHONPATH, \${\${UPS_PROD_NAME_UC}_DIR}/python)
      envSet( MUSE_ENVSET_DIR, /cvmfs/mu2e.opensciencegrid.org/DataFiles/Muse)
      addAlias(muse,source \${\${UPS_PROD_NAME_UC}_DIR}/bin/muse)
      execute("export -f muse",NO_UPS_ENV)

End:

EOL


cd ../..

mkdir -p ${VERSION}.version
cd ${VERSION}.version

cat > NULL <<EOL
FILE    = version
PRODUCT = muse
VERSION = $VERSION

FLAVOR = NULL
QUALIFIERS =

  PROD_DIR = muse/$VERSION
  UPS_DIR = ups
  TABLE_FILE = muse.table

EOL

cd ../..

tar -cjf muse-${VERSION}.bz2 muse/${VERSION} muse/${VERSION}.version

cd $OWD
exit 0
