#! /bin/bash

GITBRANCH=master
SKIPSTATUS=0
SKIPPRIVATE=0
SKIPTESTS=0
SKIPALLTESTS=0
NOAUTOCOMMIT=0
TESTMODEONLY=0
distdir=./
UNAME=`uname -n | perl -ne '/^([^.]+)/ and print $1'`
if [ $UNAME == "diefenbaker" ] ; then
    distdir=~/distro
fi

for argv ; do
    case $argv in
        -b=*)           GITBRANCH=`echo $argv | perl -pe 's/^-b=//;'`
            ;;
        -d=*)           DIST_DIR=`echo $argv | perl -pe 's/^-d=//'`
            ;;
        -skipstatus)    SKIPSTATUS=1
            ;;
        -skipalltests)  SKIPALLTESTS=1
            ;;
        -skipprivate)   SKIPPRIVATE=1
            ;;
        -skiptests)     SKIPTESTS=1
            ;;
        -noautocommit)  NOAUTOCOMMIT=1
            ;;
        -test|-t)       TESTMODEONLY=1
            ;;
        -*)   if test "$argv" == "-help" || test "$argv" == "-h" ; then
                  echo ""
              else
                  echo "Unknown argument '$argv'"
              fi
              cat <<EOF && exit;;
Usage: $0 [-t] [-d=<directory]

    -t              Run tests only, do not make a tarball
    -d=<directory>  Taret directory for the tarball ($distdir)
    -b=<gitbranch>  Check the current branch against <gitbranch> (master)
    -skipstatus     Skip 'git status' (everything must be checked in)
    -skippalltests  Do not run any test
    -skipprivate    Do not run the tests in private/
    -skiptests      Do not run the tests in t/
    -noautocommit   Do not commit version-bump and Changelog (with tag)
    -help           This message
EOF
    esac
done

# Set the directory where distributions are kept
if [ "$DIST_DIR" != "" ] ; then
    distdir=$DIST_DIR
fi
echo "Will put the distribution in: '$distdir'"

# Check git branch
mybranch=`git branch | perl -ne '/^\*\s(\S+)/ and print $1'`
if [ "$mybranch" != "$GITBRANCH" ] ; then
    echo "Branch not ok, found '$mybranch' expected '$GITBRANCH'"
    exit 10
fi

# Check git status -s
mystatus=`git status -s`
if [ "$SKIPSTATUS" != "1" ] ; then
    if [ "$mystatus" != "" ] ; then
        echo "Status not clean: $mystatus";
        exit 15
    fi
else
    if [ "$mystatus" != "" ] ; then
        echo "'git status -s' not clean: $mystatus";
    else
        echo "'git status -s' was clean!"
    fi
fi

if [ -f "Makefile" ] ; then
    make -i veryclean > /dev/null 2>&1
fi

if [ "$SKIPALLTESTS" != "1" ] ; then
    if [ "$SKIPPRIVATE" != "1" ] ; then
        # Run the private testsuite
        prove -wl private/*.pl private/*.t
        if [ $? -gt 0 ] ; then
            echo "Private tests not ok: $?"
            exit 20
        fi
    else
        echo "Skipped private tests"
    fi
    if [ "$SKIPtests" != "1" ] ; then
        # Run the public testsuite
        prove -wl t/*.t
        if [ $? -gt 0 ] ; then
            echo "Public tests not ok: $?"
            exit 25
        fi
    else
        echo "Skipped public tests"
    fi
else
    echo "Skipped all tests"
fi

if [ "$TESTMODEONLY" == "1" ] ; then
    echo "Running in test-mode, exiting"
    exit 0
fi

# Update the version in lib/Test/Smoke.pm
myoldversion=`perl -Ilib -MTest::Smoke -e 'print Test::Smoke->VERSION'`
perl -i -pe '/^(?:our\s*)?\$VERSION\s*=\s*/ && s/(\d+\.\d+)/sprintf "%.2f", $1+0.01/e' lib/Test/Smoke.pm
mynewversion=`perl -Ilib -MTest::Smoke -e 'print Test::Smoke->VERSION'`

# Update the Changes file
line="________________________________________________________________________________"
cat <<EOF > Changes
Changes on `date '+%Y-%m-%d'` for github repository at:
`git remote show origin | grep 'URL:'`

Enjoy!

`git log --name-status --pretty="$line%n[%h] by %an on %aD%n%n%w(76,4,8)%+B"`
EOF

echo "Distribution for $mynewversion (was $myoldversion)"
if [ "$NOAUTOCOMMIT" != "1" ]; then
    git commit -m "Autocommit for distribution Test::Smoke $mynewversion" lib/Test/Smoke.pm Changes
    git tag "Test-Smoke-$mynewversion"
    git push --all
fi

PERL_MM_USE_DEFAULT=y perl Makefile.PL
make all test
if [ $? -gt 0 ] ; then
    echo "make test failed: $?"
    exit 30
fi
make dist
mv -v *.tar.gz $distdir
make veryclean > /dev/null 2>&1
