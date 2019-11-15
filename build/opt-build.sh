#! /bin/bash

set -xe

if [[ -z "${TMPDIR}" ]]; then
  TMPDIR=/tmp
fi

set -u

if [ "$#" -lt "1" ] ; then
  echo "Please provide an installation path such as /opt/ICGC"
  exit 1
fi

# get path to this script
SCRIPT_PATH=`dirname $0`;
SCRIPT_PATH=`(cd $SCRIPT_PATH && pwd)`

# get the location to install to
INST_PATH=$1
mkdir -p $1
INST_PATH=`(cd $1 && pwd)`
echo $INST_PATH

# get current directory
INIT_DIR=`pwd`

CPU=`grep -c ^processor /proc/cpuinfo`
if [ $? -eq 0 ]; then
  if [ "$CPU" -gt "6" ]; then
    CPU=6
  fi
else
  CPU=1
fi
echo "Max compilation CPUs set to $CPU"

SETUP_DIR=$INIT_DIR/install_tmp
mkdir -p $SETUP_DIR/distro # don't delete the actual distro directory until the very end
mkdir -p $INST_PATH/bin
cd $SETUP_DIR

# make sure tools installed can see the install loc of libraries
set +u
export LD_LIBRARY_PATH=`echo $INST_PATH/lib:$LD_LIBRARY_PATH | perl -pe 's/:\$//;'`
export PATH=`echo $INST_PATH/bin:$PATH | perl -pe 's/:\$//;'`
export MANPATH=`echo $INST_PATH/man:$INST_PATH/share/man:$MANPATH | perl -pe 's/:\$//;'`
export PERL5LIB=`echo $INST_PATH/lib/perl5:$PERL5LIB | perl -pe 's/:\$//;'`
set -u

## vcftools
if [ ! -e $SETUP_DIR/vcftools.success ]; then
  curl -sSL --retry 10 https://github.com/vcftools/vcftools/releases/download/v${VER_VCFTOOLS}/vcftools-${VER_VCFTOOLS}.tar.gz > distro.tar.gz
  rm -rf distro/*
  tar --strip-components 2 -C distro -xzf distro.tar.gz
  cd distro
  ./configure --prefix=$INST_PATH --with-pmdir=lib/perl5
  make -j$CPU
  make install
  cd $SETUP_DIR
  rm -rf distro.* distro/*
  touch $SETUP_DIR/vcftools.success
fi

### cgpVcf
if [ ! -e $SETUP_DIR/cgpVcf.success ]; then
  curl -sSL --retry 10 https://github.com/cancerit/cgpVcf/archive/${VER_CGPVCF}.tar.gz > distro.tar.gz
  rm -rf distro/*
  tar --strip-components 1 -C distro -xzf distro.tar.gz
  cd distro
  cpanm --no-interactive --notest --mirror http://cpan.metacpan.org --notest -l $INST_PATH --installdeps .
  cpanm -v --no-interactive --mirror http://cpan.metacpan.org -l $INST_PATH .
  cd $SETUP_DIR
  rm -rf distro.* distro/*
  touch $SETUP_DIR/cgpVcf.success
fi

### alleleCount
echo "Building alleleCounter ..."
if [ ! -e $SETUP_DIR/alleleCount.success ]; then
  curl -sSL --retry 10 https://github.com/cancerit/alleleCount/archive/${VER_ALLELECOUNT}.tar.gz > distro.tar.gz
  rm -rf distro/*
  tar --strip-components 1 -C distro -xzf distro.tar.gz
  #build the C part
  cd distro
  make -C c clean
  export prefix=$INST_PATH
  make -C c -j$CPU
  cp $SETUP_DIR/distro/c/bin/alleleCounter $INST_PATH/bin/.
  #build the perl part
  cd $SETUP_DIR/distro/perl  
  cpanm --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH/ --installdeps $SETUP_DIR/distro/perl/. < /dev/null
  perl Makefile.PL INSTALL_BASE=$INST_PATH
  make
  make test
  make install
  cd $SETUP_DIR
  rm -rf distro.* distro/*  
  touch $SETUP_DIR/alleleCounter.success
fi

### impute2
if [ ! -e $SETUP_DIR/impute2.success ]; then
  curl -sSL --retry 10 https://mathgen.stats.ox.ac.uk/impute/impute_${VER_IMPUTE2}_x86_64_dynamic.tgz > distro.tar.gz
  rm -rf distro/*
  tar --no-same-owner --strip-components 1 -C distro -xzf distro.tar.gz
  cd $SETUP_DIR
  chmod 0755 $SETUP_DIR/distro/impute2
  cp $SETUP_DIR/distro/impute2 $INST_PATH/bin/.
  cd $SETUP_DIR
  rm -rf distro.* distro/*  
  touch $SETUP_DIR/impute2.success
fi