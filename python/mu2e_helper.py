#
# This class defines procedures that most SConscript files will use
# for building. In an SConscript it is created:
#
# Import('env')
# Import('mu2e_helper')
# helper=mu2e_helper(env)
#
# Then the typical functions used are
#
# helper.make_mainlib(...)
# helper.make_plugins(...)
# helper.make_dict_and_map(...)
#

import os
import string
from glob import glob


class mu2e_helper:
    """mu2e_helper: class to produce libraries"""

    def __init__(self,env):
        self.env = env
        # full path of the scons top directory (MUSE_BUILD_DIR)
        self.base = env.GetLaunchDir()
        # full path to this subdir with the SConscript 
        self.codeDir = env.GetBuildPath('SConscript').replace('/SConscript','')
        # diff, like Offline/package/src
        self.srcPath = os.path.relpath(self.codeDir,self.base) # the difference
        tokens = self.srcPath.split('/')
        if tokens[-1] == 'src' :
            tokens.remove('src')
        # the repo name, like Offline
        self.repo = tokens[0]

        # build/stub, like build/sl7-e20
        self.buildBase = env['MUSE_BUILD_BASE']

        # where dictionaries go: build/stub/Offline/tmp/codeDir/dict
        self.dictdir = self.buildBase+'/'+\
                       self.srcPath.replace(self.repo,self.repo+"/tmp")+"/dict"
        self.libdir = self.buildBase+'/'+self.repo+'/lib'
        self.bindir = self.buildBase+'/'+self.repo+'/bin'
        # change string Offline/dir/subdir/src to dir_subdir
        if self.repo == "Offline" :
            self.libstub = "mu2e_"+'_'.join(tokens[1:])
        else:
            self.libstub = self.repo.lower()+'_'.join(tokens[1:])

        # A few places we use ClassDef in order to enable a class
        # to be fully capable at the root prompt
        # Using ClassDef forces the dictionary to be linked with the main
        # class code.  Set this True to make this happen
        self.classdef = False

    # set true if ClassDef is used, to force dictionary
    # to be linked in mainlib
    def classDef(self, tf=True):
        self.classdef = tf

    def lib_link_name(self):
        return self.libstub
    def lib_file(self):
        return self.libdir+"/lib"+self.libstub+".so"
    def plugin_lib_file(self,sourcename):
        stub = sourcename[:sourcename.find('.cc')] # file name minus the .cc
        return self.libdir+"/lib"+self.libstub + '_' + stub +".so"
    def dict_file(self):
        return self.dictdir+"/"+self.libstub + '_dict.cpp'
    def dict_lib_file(self):
        if self.classdef : # dictionary is in the main lib
            return self.libdir+"/lib"+self.libstub + '.so'
        else :  # dictionary is in its own lib
            return self.libdir+"/lib"+self.libstub + '_dict.so'
    def rootmap_file(self):
        return self.libdir+"/lib"+self.libstub + "_dict.rootmap"
    def pcm_file(self):
        if self.classdef : # dictionary is in the main lib
            return self.libdir+"/lib"+self.libstub + "_rdict.pcm"
        else :  # dictionary is in its own lib
            return self.libdir+"/lib"+self.libstub + "_dict_rdict.pcm"

    #
    #   Build a list of plugins to be built.
    #
    def plugin_cc(self):
        return self.env.Glob('*_module.cc', strings=True) \
            + self.env.Glob('*_service.cc', strings=True) \
            + self.env.Glob('*_source.cc', strings=True)  \
            + self.env.Glob('*_utils.cc',strings=True)    \
            + self.env.Glob('*_tool.cc',strings=True)

    #
    #   Build a list of bin source files
    #
    def bin_cc(self):
        return self.env.Glob('*_main.cc', strings=True)

    #
    #   Build a list of .cc files that are not plugings or bins;
    #   these go into the library named after the directory.
    #
    def mainlib_cc(self):
        cclist = self.env.Glob('*.cc', strings=True)
        for cc in self.plugin_cc(): cclist.remove(cc)
        for cc in self.bin_cc(): cclist.remove(cc)
        return cclist

    #
    #   Make the main library.
    #
    def make_mainlib( self, userlibs, cppf=[], pf=[], addfortran=False ):
        mainlib_cc = self.mainlib_cc()
        if addfortran:
            fortran = self.env.Glob('*.f', strings=True)
            mainlib_cc = [ mainlib_cc, fortran ]
        # if classdef is used, force dictionary into mainlib
        if self.classdef :
            mainlib_cc.append("#/"+self.dict_file())
        if mainlib_cc:
            self.env.SharedLibrary( "#/"+self.lib_file(),
                               mainlib_cc,
                               LIBS=[ userlibs],
                               CPPFLAGS=cppf,
                               parse_flags=pf
                              )
            return self.lib_link_name()
        else:
            return ""

    #
    #   Make one plugin library
    #
    def make_plugin( self, cc, userlibs, cppf = [], pf = []):
        self.env.SharedLibrary( "#/"+self.plugin_lib_file(cc),
                           cc,
                           LIBS=[ userlibs],
                           CPPFLAGS=cppf,
                           parse_flags=pf
                           )

    #
    #   Make all plugin libraries, excluding _dict and _map; this works if
    #   all libraries need the same link list.
    #
    def make_plugins( self, userlibs, exclude_cc = [], cppf = [], pf = [] ):
        plugin_cc = self.plugin_cc()
        for cc in exclude_cc: plugin_cc.remove(cc)
        for cc in plugin_cc:
            self.make_plugin(cc,userlibs, cppf, pf)

    #
    #   Make the dictionary and rootmap plugins.
    #
    def make_dict_and_map( self, userlibs=[], pf_dict=[] ):
        cfs = self.codeDir+'/classes.h'
        xfs = self.codeDir+'/classes_def.xml'

        sources = ['classes.h','classes_def.xml']
        targets = ["#/"+self.dict_file(),
                   "#/"+self.rootmap_file(),
                   "#/"+self.pcm_file() ]
        dflag = ""
        if self.env["BUILD"] == "debug":
            dflag = ""
        else:
            dflag = "-DNDEBUG"
        self.env.DictionarySource( targets, sources ,
                                   LIBTEXT=self.dict_lib_file(),
                                   DEBUG_FLAG=dflag)
        # if classdef is used, do not make the dictionary into its own lib,
        # it will be put in the mainlib
        if self.classdef :
            return
        # make lib for the dictionary
        self.env.SharedLibrary( "#/"+self.dict_lib_file(),
                                "#/"+self.dict_file(),
                                LIBS=[ userlibs ],
                                parse_flags=pf_dict
                                )
    #
    #   Make a bin based on binname_main.cc -> binname
    #
    def make_bin( self, target, userlibs=[], otherSource=[]):
        sourceFiles =  [ target+"_main.cc" ] + otherSource
        self.env.Program(
            target = '#/'+self.bindir+"/"+target,
            source = sourceFiles,
            LIBS   = userlibs
            )

    #
    #   Make any combination source->target
    #
    def make_generic( self, source, target, command ):
        topSources = []
        topTargets = []
        for s in source :
            topSources.append('#/'+s)
        for t in target :
            topTargets.append('#/'+t)
        self.env.GenericBuild( topTargets, topSources, COMMAND=command)
