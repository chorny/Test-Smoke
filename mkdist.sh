#! /bin/sh

# $Id$

SMOKE_PERL=perl
SMOKE_PROVE=prove
SMOKE_COVER=cover
for argv
    do case $argv in
        -t)   SMOKE_TEST_ONLY=1;;
        -e)   SMOKE_COVERAGE=1;;
        -c)   SMOKE_CI_FILES=1;;
        -s)   SMOKE_CI_SNAP=1;;
        -d=*) SMOKE_DIST_DIR=`echo $argv | perl -pe 's/^-d=//'`;;
        -58)  SMOKE_PERL=/opt/perl584/bin/perl5.8.4 
              SMOKE_PROVE=/opt/perl584/bin/prove5.8.4
              SMOKE_COVER=/opt/perl584/bin/cover;;
        -59)  SMOKE_PERL=/opt/bleadperl/bin/perl5.9.2
              SMOKE_PROVE=/opt/bleadperl/bin/prove5.9.2
              SMOKE_COVER=/opt/bleadperl/bin/cover;;
        -*)   if test "$argv" == "--help" || test "$argv" == "-h" ; then
                  echo ""
              else
                  echo "Unknown argument '$argv'"
              fi
              cat <<EOF && exit;;
Usage: $0 [-t] [-d=<directory]

    -t              Run tests only, do not make a tarball
    -e              Extend testing by running coverage (sets -t)
    -c              Commit the auto generated files Changes and SIGNATURE
    -s              Commit this tree as a snapshot (set by -c)
    -58             Use the latest 5.8 installed (needed for -e)
    -59             Use the latest 5.9 installed
    -d=<directory>  Taret directory for the tarball

EOF
    esac
done

# Force snapshot for -c
if [ "$SMOKE_CI_FILES" == "1" ] ; then
    SMOKE_CI_SNAP=1
fi

# Set the directory where distributions are kept
distdir=./
if [ "`uname -n`" == "fikkie" ] ; then
    distdir=~/distro
fi
if [ "$SMOKE_DIST_DIR" != "" ] ; then
    distdir=$SMOKE_DIST_DIR
fi
echo "Will put the distribution in: '$distdir'"
echo "Will use $SMOKE_PERL  for perl"
echo "Will use $SMOKE_PROVE for proving"

# Force testingmode for Coverage!
if [ "$SMOKE_COVERAGE" == "1" ] ; then
    SMOKE_TEST_ONLY=1
    echo "Will use $SMOKE_COVER for coverage"
fi

trap 'if [ $? ] ; then echo "An error while testing..."; fi ; exit' 0

# Check if all the distributed perl-files compile
# Check if all the distibuted files with POD are pod_ok
$SMOKE_PROVE private/test_*.pl || exit

if [ "$SMOKE_TEST_ONLY" == "1" ] ; then
    if [ "$SMOKE_COVERAGE" == "1" ] ; then
        $SMOKE_PROVE -Ilib private/*.t
        $SMOKE_COVER -delete
        HARNESS_PERL_SWITCHES=-MDevel::Cover \
            $SMOKE_PROVE -Ilib t/*.t
        PROVE_ERROR=$?
        $SMOKE_COVER
        if [ "$PROVE_ERROR" != "0" ] ; then exit $PROVE_ERROR ; fi
    else
        $SMOKE_PROVE -I lib private/*.t t/*.t || exit
    fi
    echo "SMOKE_TEST_ONLY was set, quitting..."
    trap '' 0
    exit
else
    $SMOKE_PROVE -I lib private/smoker_*.t || exit
fi

# Clean up before we start
make -i veryclean > /dev/null 2>&1

SMOKE_VERSION=`$SMOKE_PERL -Ilib -MTest::Smoke -e 'print Test::Smoke->VERSION'`
if [ "$SMOKE_VERSION" == "" ] ; then
    echo "No SMOKE_VERSION"
    exit
else
    echo "Create distribution for Test::Smoke $SMOKE_VERSION"
fi
if [ "$SMOKE_CI_FILES" == "1" ] ; then
    # I keep forgetting about Changes, so automate:
    svnchanges > Changes
    svn ci Changes -m "* regen Changes for $SMOKE_VERSION"
else
    echo "Skipping commit of 'Changes'"
fi

# Now create the Makefile and and run the public test-suite
PERL_MM_USE_DEFAULT=y $SMOKE_PERL Makefile.PL

make

make test || exit

# Create the distribution and move it to the distribution directory
perl -i -pe 's/^#?local-user abeltje/local-user abeltje/' ~/.gnupg/options
make dist
perl -i -pe 's/^local-user abeltje/#local-user abeltje/' ~/.gnupg/options
mv -v *.tar.gz $distdir

# Clean up!
make veryclean > /dev/null
rm -f */*/*/*~

if [ "$SMOKE_CI_FILES" == "1" ] ; then
    # Also commit the newly generated SIGNATURE
    svn ci SIGNATURE -m "* regen SIGNATURE for $SMOKE_VERSION"
else
    echo "Skipping commit of 'SIGNATURE'"
fi

SMOKE_SOURCE=`svn info | perl -ne 's/^Url: // and print'`
SMOKE_SOURCE=`echo $SMOKE_SOURCE | perl -pe 's|http://([^/]+)/|http://yola/|'`
#SMOKE_SNAP_BASE="http://source.test-smoke.org/svn/snapshots/"
SMOKE_SNAP_BASE="http://yola/svn/snapshots/"
SMOKE_SNAP_DIR="${SMOKE_SNAP_BASE}Test-Smoke-$SMOKE_VERSION"
SMOKE_SNAP_MSG=svnmsg.ci
if [ "$SMOKE_CI_SNAP" == "1" ] ; then
    echo "Snapshot: $SMOKE_SNAP_DIR"
    # Create a snapshot in the repository
    echo "* [SVN] Create a branch for $SMOKE_VERSION" > $SMOKE_SNAP_MSG
    svn cp $SMOKE_SOURCE $SMOKE_SNAP_DIR -F $SMOKE_SNAP_MSG
    rm -f $SMOKE_SNAP_MSG
else
    echo "Skipping branch from '$SMOKE_SOURCE' ($SMOKE_VERSION)"
fi
