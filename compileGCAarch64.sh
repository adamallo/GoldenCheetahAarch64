#!/bin/bash

#TODO: Eventually, I could add tags to all the optional libraries

#Script configuration
############################################

#Getopts defaults
version="v3.6"
njobs=4
dist=0
SStepCol=b
StepCol=bd
ErrCol=r
WarnCol=y

#HARDCODED
##Library information
###Paths #TODO working here to have the paths an names here and use them in multiple places below
homebrewPath="/opt/homebrew/lib/"
gslPath="/opt/homebrew/opt/gsl/"
gslFile="/lib/libgsl.dylib"
libicalPath=$homebrewPath
libicalName="libical.3.dylib"
libusbPath=$homebrewPath
libusbName="libusb-1.0.dylib"
libsampleratePath=$homebrewPath
libsamplerateName="libsamplerate.dylib"
libicu4cPath="/opt/homebrew/opt/icu4c/lib/"
libftd2xxName="libftd2xx.1.4.24.dylib"

##Compilation environment. This may change with newer/different versions in homebrew
export PATH="/opt/homebrew/opt/bison/bin:$PATH"
export PATH="/opt/homebrew/opt/m4/bin:$PATH"
export PATH="/opt/homebrew/opt/qt@5/bin:$PATH"
export LDFLAGS="-L/opt/homebrew/opt/qt@5/lib"
export CPPFLAGS="-I/opt/homebrew/opt/qt@5/include"
export PKG_CONFIG_PATH="/opt/homebrew/opt/qt@5/lib/pkgconfig"
############################################

#Functions
############################################
cecho() {
  local code=`tput sgr0`
  case "$1" in
    black  | bk) color=`tput setaf 0`;;
    red    |  r) color=`tput setaf 1`;;
    green  |  g) color=`tput setaf 2`;;
    yellow |  y) color=`tput setaf 3`;;
    blue   |  b) color=`tput setaf 4`;;
    purple |  p) color=`tput setaf 5`;;
    cyan   |  c) color=`tput setaf 6`;;
    gray   | gr) color=`tput setaf 7`;;
	bold   | bd) color=`tput bold`;;
    *) local text="$1"
  esac
  [ -z "$text" ] && local text="$color$2${code}"
  echo -e "$text"
}
############################################


#Getopts
############################################
usageMessage="\n\nUsage: [sudo] $0 [-h] [-v version] [-d] baseDirectory.\nCommand line options:\n\t-v: GoldenCheetah version to compile\n\t-d: Deploy app to share (both by itself and in a dmg image)\nDefaults:\n\tversion: $version\n\tnjobs: $njobs\nCalling $0 with sudo is recommended to avoid having to input your password several times\n\n"
function usage {
    if [[ $# -eq 1 ]]
    then
        >&2 cecho $ErrCol "\nERROR: $1"
		>&2 cecho "$usageMessage"
    else
        >&2 cecho "$usageMessage"
    fi
    
    exit 1
}

#The first : indicates silent checking
#The : after each option indicates that they require an argument
[ $# -eq 0 ] && usage
while getopts ":v:j:hd" options
do
    case "${options}" in 
        v)
            version=${OPTARG}
            ;;
        j)
            njobs=${OPTARG}
			[[ "$njobs" =~ ^[0-9]+$ ]] || usage "njobs ($njobs) must be a integer"
            ;;
        h)
            usage
            ;;
		d)
			dist=1 
			;;
        *)
            usage "wrong input option"
            ;;
    esac
done

#After this, there would be positional arguments available
shift "$((OPTIND-1))"
[ $# -eq 1 ] || usage "One and only one positional argument with the directory to base the compilation required"
[ "$EUID" -eq 0 ] || cecho $WarnCol "WARNING: This script is better run with sudo to avoid having to input your password several times\n"
basedir=$1
cecho bd "\nRunning $0 with the following options:\n\t-GC version: $version\n\t-Number of parallel compilation jobs: $njobs\n\t-Distribution: $dist\n\t-Base directory: $basedir\n"
############################################

mkdir -p $basedir
cd $basedir
basepath=$PWD

#Corresponding with travis before_install.sh
############################################

##Brewer and brewer packages
# TODO: untested section
cecho $StepCol "\nInstalling dependencies using Homebrew, if needed"
if ! command -v brew &> /dev/null;
then
	>&2 cecho $WarnCol "WARNING: Homebrew will be installed now and will required human input. You can read about this package manager for macOS @ https://brew.sh/\n"
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	>&2 cecho $WarnCol "WARNING: Read the last steps from homebrew's installation. This is not needed for GoldenCheetah or this compilation script, but it would be for you to keep using Homebrew and the tools it installed afterwards.\n"
	read -s -n 1 -p "Press any key to continue"
	eval "$(/opt/homebrew/bin/brew shellenv)" #This command adds Homebrew to path, manpath, and infopath for this session
fi

#TODO This is pretty ugly and could be done in some nice array loops but it does work
#Required
command -v qtdiag &> /dev/null || brew install qt5
command -v m4 &> /dev/null || brew install m4
command -v bison &> /dev/null || brew install bison
command -v gcp &> /dev/null || brew install coreutils
[ -d "$gslPath" ] || brew install gsl
#Required?
[ -f "$libicalPath/$libicalName" ] ||  brew install libical
[ -f "$libusbPath/$libusbName" ] ||  brew install libusb
[ -f "$libsampleratePath/$libsamplerateName" ] ||  brew install libsamplerate
#Optional
#TODO only if r
command -v r &> /dev/null || brew install r

cecho $StepCol "Done\n"

#TODO these links and filenames should be generalized and hardcoded above so that this is easy to update in the future, especially for python, R, and vlc (I do not know if we expet srm and d2xx to change much)
cecho $StepCol "\nDownloading, compiling, and installing dependencies not in Homebrew"

#macdeployqtfix
#This adds python3 as a dependency, but it is present after installing Xcode  Is it always present in mac with homebrew?
cecho $SStepCol "macdeployqtfix"
if [ ! -f macdeployqtfix/macdeployqtfix.py ];then
	git clone https://github.com/tamlok/macdeployqtfix.git
else
	cecho "Already present"
fi
cecho $SStepCol "Done"

#SRMIO
cecho $SStepCol "SRMIO"
if ! command -v srmdump &> /dev/null ; then
	curl -L -O https://github.com/rclasen/srmio/archive/v0.1.1git1.tar.gz
	tar xf v0.1.1git1.tar.gz
	cd srmio-0.1.1git1
	sh genautomake.sh
	./configure --disable-shared --enable-static
	make -j$njobs --silent
	sudo make install
	cd ..
else
	cecho "Already present"
fi
cecho $SStepCol "Done"

# D2XX
# TODO I want to generalize this to any libftd2xx version?
cecho $SStepCol "D2XX"
if [ ! -f /usr/local/lib/libftd2xx.1.4.24.dylib ];then
	if [ -z "$(ls -A D2XX)" ]; then
	    curl -O https://ftdichip.com/wp-content/uploads/2021/05/D2XX1.4.24.zip
	    unzip D2XX1.4.24.zip
	    hdiutil mount D2XX1.4.24.dmg
		mkdir D2XX
	    cp /Volumes/dmg/release/build/libftd2xx.1.4.24.dylib D2XX
	    cp /Volumes/dmg/release/build/libftd2xx.a D2XX
	    cp /Volumes/dmg/release/*.h D2XX
		hdiutil detach /Volumes/dmg
	fi
	sudo cp D2XX/libftd2xx.1.4.24.dylib /usr/local/lib
else
	cecho "Already present"
fi
cecho $SStepCol "Done"

# VLC
cecho $SStepCol "VLC"
if [ "$(ls -A /usr/local/lib/libvlc*.dylib | wc -l)" -eq 0 ]; then
	if [ -z "$(ls -A VLC)" ]; then
	    curl -O http://download.videolan.org/pub/videolan/vlc/3.0.20/macosx/vlc-3.0.20-arm64.dmg
	    hdiutil mount vlc-3.0.20-arm64.dmg
	    mkdir VLC
		cp -R "/Volumes/VLC media player/VLC.app/Contents/MacOS/include" VLC/include
	    cp -R "/Volumes/VLC media player/VLC.app/Contents/MacOS/lib" VLC/lib
	    cp -R "/Volumes/VLC media player/VLC.app/Contents/MacOS/plugins" VLC/plugins
	    rm -f VLC/plugins/plugins.dat
	fi
	sudo cp VLC/lib/libvlc*.dylib /usr/local/lib
else
	cecho "Already present"
fi
cecho $SStepCol "Done"

#These actually correspont to before_script.sh but make more sense here
# R libraries
cecho $SStepCol "Checking R libraries are installed or installing them:"
2>&1 Rscript -e 'if(!require("Rcpp")) install.packages("Rcpp", repos="https://cloud.r-project.org")' | awk '!/^Loading required package: Rcpp$/'
2>&1 Rscript -e 'if(!require("RInside")) install.packages("RInside", repos="https://cloud.r-project.org")' | awk '!/^Loading required package: RInside$/'
cecho $SStepCol "Done"

cecho $StepCol "Done\n"
############################################
#Getting the sources and checking out the proper version
############################################
cecho $StepCol "Downloading sources and checking out version $version (if needed)"
mkdir -p Projects
cd Projects
if [ -d GoldenCheetah ]; then
	foundTag=$(git -C GoldenCheetah/ describe --tag HEAD)
	if [ "$foundTag" == "$version" ];then
		cecho "Repo with the proper tag found, skipping git download and checkout"
	else
		cecho $ErrCol "Repo with the wrong tag found, delete it and execute this script again"
		exit 1
	fi
else
	git clone https://github.com/GoldenCheetah/GoldenCheetah.git
	git checkout $version
fi
cecho $StepCol "Done\n"
############################################

##Corresponding with travis before_script.sh
############################################
cd GoldenCheetah

cecho $StepCol "\nConfiguring compilation"

#Patching sources for ARM
sed -i "" "s/ finite/ isfinite/g" contrib/levmar/compiler.h

#Configuring compilation
cp qwt/qwtconfig.pri.in qwt/qwtconfig.pri
cp src/gcconfig.pri.in src/gcconfig.pri

#Required Configs
##GSL
sed -i "" "s/^#GSL_INCLUDES.*$/GSL_INCLUDES = \/opt\/homebrew\/opt\/gsl\/include\//" src/gcconfig.pri
sed -i "" "s/^#GSL_LIBS = -lgsl/GSL_LIBS = -L\/opt\/homebrew\/opt\/gsl\/lib\/ -lgsl/" src/gcconfig.pri
##Bison
sed -i "" "s/^#QMAKE_YACC = bison/QMAKE_YACC = bison/" src/gcconfig.pri
sed -i "" "s/^#QMAKE_MOVE = cp/QMAKE_MOVE = cp/" src/gcconfig.pri
##Libz
sed -i "" "s/^#LIBZ_LIBS/LIBZ_LIBS/" src/gcconfig.pri

#Compilation configs
##GC version
echo DEFINES += GC_VERSION=$(git describe --tags HEAD | sed "s/[a-zA-Z]//g") >> src/gcconfig.pri #Not tested with untagged versions
##Compiler optimization
sed -i "" "s/^#QMAKE_CXXFLAGS += -O3/QMAKE_CXXFLAGS += -O3/" src/gcconfig.pri
##GC compilation style
sed -i "" "s|#\(CONFIG += release.*\)|\1 static |" src/gcconfig.pri

#Miscelanea from before_script.sh
sed -i "" "s|#\(DEFINES += GC_WANT_ROBOT.*\)|\1 |" src/gcconfig.pri

#Optional library configs
##D2XX
[ "$dist" -eq 1 ] && sed -i "" "s|libname = \"libftd2xx.*.dylib\"|libname = \"@executable_path/../Frameworks/$libftd2xxName\"|" src/FileIO/D2XX.cpp || sed -i "" "s|libname = .*libftd2xx.*.dylib\"|libname = \"$libftd2xxName\"|" src/FileIO/D2XX.cpp #Safe to re-run changing -d option
sed -i "" "s|#\(D2XX_INCLUDE =.*\)|\1 $basepath/D2XX|" src/gcconfig.pri
sed -i "" "s|#\(D2XX_LIBS    =.*\)|\1 -L$basepath/D2XX -lftd2xx|" src/gcconfig.pri
##SRMIO
sed -i "" "s|#\(SRMIO_INSTALL = \)|\1 /usr/local|" src/gcconfig.pri
##VLC & VIDEO
sed -i "" "s|#\(VLC_INSTALL =.*\)|\1 $basepath/VLC|" src/gcconfig.pri
sed -i "" "s|\(DEFINES += GC_VIDEO_NONE.*\)|#\1 |" src/gcconfig.pri
sed -i "" "s|#\(DEFINES += GC_VIDEO_VLC.*\)|\1 |" src/gcconfig.pri
##CloudDB
#sed -i "" "s|^#CloudDB|CloudDB|" src/gcconfig.pri #TODO we need secrets.h for this
##R
sed -i "" "s|#\(DEFINES += GC_WANT_R.*\)|\1 |" src/gcconfig.pri
sed -i "" "s|#\(HTPATH = ../httpserver.*\)|\1 |" src/gcconfig.pri

# Patch Secrets.h
# To use these, I would need to get my own keys and add them to the gcconfig.pri
# in this form: DEFINES += GC_TWITTER_CONSUMER_SECRET="xxxxxxx"
# In the original compilation they were encrypted using travis, which decripts them and makes them available as variables
#sed -i "" "s/__GC_GOOGLE_CALENDAR_CLIENT_SECRET__/"$GC_GOOGLE_CALENDAR_CLIENT_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_STRAVA_CLIENT_SECRET__/"$GC_STRAVA_CLIENT_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_DROPBOX_CLIENT_SECRET__/"$GC_DROPBOX_CLIENT_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_CYCLINGANALYTICS_CLIENT_SECRET__/"$GC_CYCLINGANALYTICS_CLIENT_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_TWITTER_CONSUMER_SECRET__/"$GC_TWITTER_CONSUMER_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_DROPBOX_CLIENT_ID__/"$GC_DROPBOX_CLIENT_ID"/" src/Core/Secrets.h
#sed -i "" "s/__GC_MAPQUESTAPI_KEY__/"$GC_MAPQUESTAPI_KEY"/" src/Core/Secrets.h
#sed -i "" "s/__GC_CLOUD_DB_BASIC_AUTH__/"$GC_CLOUD_DB_BASIC_AUTH"/" src/Core/Secrets.h
#sed -i "" "s/__GC_CLOUD_DB_APP_NAME__/"$GC_CLOUD_DB_APP_NAME"/" src/Core/Secrets.h
#sed -i "" "s/__GC_GOOGLE_DRIVE_CLIENT_ID__/"$GC_GOOGLE_DRIVE_CLIENT_ID"/" src/Core/Secrets.h
#sed -i "" "s/__GC_GOOGLE_DRIVE_CLIENT_SECRET__/"$GC_GOOGLE_DRIVE_CLIENT_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_GOOGLE_DRIVE_API_KEY__/"$GC_GOOGLE_DRIVE_API_KEY"/" src/Core/Secrets.h
#sed -i "" "s/__GC_WITHINGS_CONSUMER_SECRET__/"$GC_WITHINGS_CONSUMER_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_NOKIA_CLIENT_SECRET__/"$GC_NOKIA_CLIENT_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_SPORTTRACKS_CLIENT_SECRET__/"$GC_SPORTTRACKS_CLIENT_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/OPENDATA_DISABLE/OPENDATA_ENABLE/" src/Core/Secrets.h
#sed -i "" "s/__GC_CLOUD_OPENDATA_SECRET__/"$GC_CLOUD_OPENDATA_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_NOLIO_CLIENT_ID__/"$GC_NOLIO_CLIENT_ID"/" src/Core/Secrets.h
#sed -i "" "s/__GC_NOLIO_SECRET__/"$GC_NOLIO_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_RWGPS_API_KEY__/"$GC_RWGPS_API_KEY"/" src/Core/Secrets.h
#sed -i "" "s/__GC_XERT_CLIENT_SECRET__/"$GC_XERT_CLIENT_SECRET"/" src/Core/Secrets.h
#sed -i "" "s/__GC_AZUM_CLIENT_SECRET__/"$GC_AZUM_CLIENT_SECRET"/" src/Core/Secrets.h

#Update translations
lupdate src/src.pro > /dev/null 2>&1 

cecho $StepCol "Done\n"
############################################

##Corresponding with travis script.sh
############################################
#compile
# TODO remove distclean or not? Good for debugging
cecho $StepCol "\nStarting compilation"
CC=clang CXX=clang++ make distclean
CC=clang CXX=clang++ qmake -makefile -recursive QMAKE_CXXFLAGS_WARN_ON+="-Wno-unused-private-field -Wno-c++11-narrowing -Wno-deprecated-declarations -Wno-deprecated-register -Wno-nullability-completeness -Wno-sign-compare -Wno-inconsistent-missing-override" QMAKE_CFLAGS_WARN_ON+="-Wno-deprecated-declarations -Wno-sign-compare"

#Patching makefiles to use gcp instead of cp
sed -i "" "s/^\(COPY.*\)cp/\\1gcp/g" src/Makefile
sed -i "" "s/^\(INSTALL.*\)cp/\\1gcp/g" src/Makefile

#make
CC=clang CXX=clang++ make qmake_all
CC=clang CXX=clang++ make -j$njobs sub-qwt --silent
CC=clang CXX=clang++ make -j$njobs sub-src --silent || CC=clang CXX=clang++ make sub-src
cecho $StepCol "Done\n"
############################################

##Corresponding with travis after_success.sh
############################################

cecho $StepCol "\nAdding uninstalled libraries to the app"
cd src
mkdir -p GoldenCheetah.app/Contents/Frameworks

# Add VLC dylibs and plugins
# This is needed even if the code will not be distributed
cp $basepath/VLC/lib/libvlc.dylib $basepath/VLC/lib/libvlccore.dylib GoldenCheetah.app/Contents/Frameworks
cp -R $basepath/VLC/plugins GoldenCheetah.app/Contents/Frameworks
cecho $StepCol "Done\n"

if [ "$dist" -eq 1 ]
then
	cecho $StepCol "\nPreparing app for distribution"
	# This is a hack to include libicudata.*.dylib, not handled by macdployqt[fix] #It works without this, but I am leaving it just in case I find a problem later
	#cp $libicu4cPath/libicudata.*.dylib GoldenCheetah.app/Contents/Frameworks
	
	# Initial deployment using macdeployqt
	cecho $SStepCol "Deployment with macdeployqt and macdeployqtfix"
	macdeployqt GoldenCheetah.app -executable=GoldenCheetah.app/Contents/MacOS/GoldenCheetah
	
	# Substitutes the manual loop across libs in after_success.sh
	python3 $basepath/macdeployqtfix/macdeployqtfix.py GoldenCheetah.app/Contents/MacOS/GoldenCheetah $(which qmake | sed "s/bin\/qmake//")
	cecho $SStepCol "Done"
	
	# Re-signs the app after macdeployqt and macdeployqtfix's modifications
	cecho $SStepCol "Signing app"
	sudo codesign --force --deep -s - GoldenCheetah.app #TODO Need a proper signature for distribution, this only works in the computer that signed it
	cecho $SStepCol "Done"
	
	# Makes the dmg
	cecho $SStepCol "Making final DMG for distribution"
	rm -f GoldenCheetah.dmg
	macdeployqt GoldenCheetah.app -fs=hfs+ -dmg
	cecho $SStepCol "Done"
	
	cecho $StepCol "Done\n"
fi
############################################
