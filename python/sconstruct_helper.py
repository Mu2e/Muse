#
# Define some helper functions which provide text such as build options
# and library lists to be used in SConstruct.  Also there are a few functions
# that perform little tasks - put here to keep SConstruct more readable.
#

from glob import glob
import os, re, string

import sys
import subprocess

# Check that some of the required environment variables have been set
# and derive and check other pieces of the environment
# return a dictionary with mu2eOpts
def mu2eEnvironment():
    mu2eOpts = {}

    # the directory that includes local repos and 'build'
    workDir = os.environ['MUSE_WORK_DIR']

    # subdir where built files are put
    buildBase = 'build/'+os.environ['MUSE_STUB']

    mu2eOpts['workDir'] = workDir
    mu2eOpts['buildBase'] = buildBase
    mu2eOpts['tmpdir'] = buildBase+'/tmp'
    mu2eOpts['libdir'] = buildBase+'/lib'
    mu2eOpts['bindir'] = buildBase+'/bin'
    mu2eOpts['gendir'] = buildBase+'/gen'

# a list of repos in link order
    mu2eOpts['repos'] = os.environ['MUSE_REPOS']

    # prof or debug
    mu2eOpts['build'] = os.environ['MUSE_BUILD']
    if len(os.environ['MUSE_G4VIS'])>0:
        mu2eOpts['g4vis'] = os.environ['MUSE_G4VIS']
    else:
        mu2eOpts['g4vis'] = 'none'

    if len(os.environ['MUSE_G4ST'])>0:
        mu2eOpts['g4mt'] = 'off'
    else:
        mu2eOpts['g4mt'] = 'on'

    if len(os.environ['MUSE_G4VG'])>0:
        mu2eOpts['g4vg'] = 'on'
    else:
        mu2eOpts['g4vg'] = 'off'

    if len(os.environ['MUSE_TRIGGER'])>0:
        mu2eOpts['trigger'] = 'on'
    else:
        mu2eOpts['trigger'] = 'off'

    if "MU2E_SPACK" in os.environ:
        mu2eOpts['spack'] = True
    else:
        mu2eOpts['spack'] = False

    return mu2eOpts

# the list of root libraries
# This comes from: root-config --cflags --glibs
def rootLibs():
    return [ 'GenVector', 'Core', 'RIO', 'Net', 'Hist', 'MLP', 'Graf', 'Graf3d', 'Gpad', 'Tree',
             'Rint', 'Postscript', 'Matrix', 'Physics', 'MathCore', 'Thread', 'Gui', 'm', 'dl' ]


# the include path
def cppPath(mu2eOpts):

    path = []
    # the directory containing the local repos
    path.append(mu2eOpts["workDir"])
    # the backing build areas style
    if os.environ.get('MUSE_BACKING') :
        for bdir in os.environ['MUSE_BACKING'].split():
            path.append(bdir)

    if os.environ.get('MUSE_VIEW_INC') :
        for vdir in os.environ['MUSE_VIEW_INC'].split(':'):
            path.append(vdir)
        # quit now since this should be everything..
        return path

    path = path + [
        os.environ['ART_INC'],
        os.environ['ART_ROOT_IO_INC'],
        os.environ['CANVAS_INC'],
        os.environ['BTRK_INC'],
        os.environ['KINKAL_INC'],
        os.environ['MESSAGEFACILITY_INC'],
        os.environ['FHICLCPP_INC'],
        os.environ['HEP_CONCURRENCY_INC'],
        os.environ['SQLITE_INC'],
        os.environ['CETLIB_INC'],
        os.environ['CETLIB_EXCEPT_INC']
        ]
    if 'NLOHMANN_JSON_INC' in os.environ:
        path = path + [ os.environ['NLOHMANN_JSON_INC'] ]
    path = path + [
        os.environ['BOOST_INC'],
        os.environ['CLHEP_INC'] ]
    if 'CPPUNIT_DIR' in os.environ:
        path = path + [ os.environ['CPPUNIT_DIR']+'/include' ]
    if 'HEPPDT_INC' in os.environ:
        path = path + [ os.environ['HEPPDT_INC' ] ]
    path = path + [ os.environ['ROOT_INC'] ]
    if 'OPENBLAS_INC' in os.environ:
        path = path + [ os.environ['OPENBLAS_INC' ] ]
    path = path + [
        os.environ['XERCES_C_INC'],
        os.environ['TBB_INC'] ]
    if 'MU2E_ARTDAQ_CORE_INC' in os.environ: # Old
        path = path + [ os.environ['MU2E_ARTDAQ_CORE_INC' ] ]
    else: # New
        path = path + [ os.environ['ARTDAQ_CORE_MU2E_INC' ] ]
    if 'PCIE_LINUX_KERNEL_MODULE_INC' in os.environ:
        path = path + [ os.environ['PCIE_LINUX_KERNEL_MODULE_INC' ] ]
    elif 'MU2E_PCIE_UTILS_INC' in os.environ:
        path = path + [ os.environ['MU2E_PCIE_UTILS_INC' ] ]
    path = path + [
        os.environ['ARTDAQ_CORE_INC'],
        os.environ['TRACE_INC'],
        os.environ['GSL_INC'],
        os.environ['POSTGRESQL_INC'],
        os.environ['PYTHON_INCLUDE']
        ]

    return path

# the ld_link_library path
def libPath(mu2eOpts):

    path = []
    if 'LD_LIBRARY_PATH' in os.environ:
        for dir in os.environ['LD_LIBRARY_PATH'].split(":"):
            path.append(dir)
    if 'MUSE_LIBRARY_PATH' in os.environ:
        for dir in os.environ['MUSE_LIBRARY_PATH'].split(":"):
            path.append(dir)

    return path

# create a list of paths to set as RPATH during the link
def collectRpath(mu2eOpts):
    paths = []
    if not mu2eOpts['spack']:
        return paths
    # repos in MUSE_WORK_DIR
    localrepos = os.environ.get('MUSE_LOCAL_REPOS')

    # MUSE_LIBRARY_PATH is filled from
    # the envset, with paths to the spack environment
    # and in museSetup, with paths to the local repos

    llp = os.environ.get('MUSE_LIBRARY_PATH')
    if not llp :
        return paths

    for pp in llp.split(':'):

        # first see if this is a repo in the working dir
        localrepo = None
        if localrepos :
            for rr in localrepos.split() :
                test = mu2eOpts['workDir']+"/"+\
                       mu2eOpts['buildBase']+"/"+rr+"/lib"
                if pp == test :
                    # this is a local repo
                    localrepo = rr

        if localrepo :
            # set RPATH of other libs relative to the lib being linked
            paths.append( "\\\$${ORIGIN}/../../" + localrepo + "/lib" )
        else :
            # use the full path as RPATH
            # if it is not local and not on cvmfs, it won't be relocatable
            if pp.split('/')[1] != "cvmfs" :
                print("Warning RPATH not on cvmfs, may not work for grid jobs")
                print("   ",pp)
            paths.append(pp)

    return paths

# Define the compiler and linker options.
# These are given to scons using its Evironment.MergeFlags call.
def mergeFlags(mu2eOpts):
    build = mu2eOpts['build']

    std = '-std=c++17'
    compf = os.environ.get('MUSE_COMPILER_E')
    if compf :
        nn = int(compf[1:])
        if nn >= 27 :
            std = '-std=c++20'

    cppflags = []
    flagstr = os.environ.get('MUSE_CPPFLAGS')
    if flagstr :
        cppflags = flagstr.split()

    flags = [std,'-Wall','-Wno-unused-local-typedefs','-g',
             '-Werror','-pedantic',
             # add as defaults June 2024
             # -Wtype-limits -Wimplicit-fallthrough -Wunused-but-set-parameter
             # add when root and boost are ready
             #'-Wdeprecated-copy', '-Wdeprecated-copy-dtor',
             '-Wl,--no-undefined','-gdwarf-2', '-Wl,--as-needed',
             '-Werror=return-type','-Winit-self','-Woverloaded-virtual']
    flags = flags + cppflags

    if build == 'prof':
        flags = flags + [ '-O3', '-fno-omit-frame-pointer', '-DNDEBUG' ]
    elif build == 'debug':
        flags = flags + [ '-O0' ]

    rpaths = collectRpath(mu2eOpts)
    for rp in rpaths :
        flags.append('-Wl,-rpath,'+rp)

    return flags


# Prepare some shell environmentals in a form to be pushed
# into the scons environment.
def exportedOSEnvironment():
    osenv = {}
    for var in [ 'LD_LIBRARY_PATH',  'GCC_FQ_DIR',  'PATH', 'PYTHONPATH',
                 'ROOTSYS', 'PYTHON_ROOT', 'PYTHON_DIR', 'SQLITE_FQ_DIR',
                 'MUSE_WORK_DIR', 'MUSE_BUILD_BASE']:
        if var in os.environ.keys():
            osenv[var] = os.environ[var]
    return osenv

# list of BaBar libs
def BaBarLibs():
    return [ 'BTrk_KalmanTrack', 'BTrk_DetectorModel', 'BTrk_TrkBase',
             'BTrk_BField','BTrk_BbrGeom', 'BTrk_difAlgebra',
             'BTrk_ProbTools','BTrk_BaBar', 'BTrk_MatEnv' ]

# Walk the directory tree to locate all SConscript files.
# this runs in the scons top source dir, which is MUSE_WORK_DIR
def sconscriptList(mu2eOpts):
    ss = []
    for repo in set(mu2eOpts['repos'].split()):
        if not os.path.islink(repo):
            for root, dirs, files in os.walk(repo, followlinks = False):
                if 'SConscript' in files:
                    ss.append(os.path.join(root, 'SConscript'))

    return ss



# with -c, scons will remove all dependant files it knows about
# but when a source file is deleted:
# - the .os file will be left in the build dir
# - the dict and lib now contain extra objects
# so explicitly delete all files left in the build dir
def extraCleanup(mu2eOpts):
    for top, dirs, files in os.walk(mu2eOpts['buildBase']):
        for name in files:
            if name != ".musebuild":
                ff =  os.path.join(top, name)
                print("removing file ", ff)
                os.unlink (ff)
