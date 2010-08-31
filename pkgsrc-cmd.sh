#!/bin/sh

# The umask setting makes everything we do group writable, which is a requirement for stuff
# we leave in the VO software area. If we didn't, only the original user would be able to
# modify or remove these files.
umask 002

# This is the location to fetch pkgsrc.tar.gz from. It's a fast mirror.
#pkgsrc_url=ftp://ftp.nl.netbsd.org/pub/NetBSD/packages/pkgsrc.tar.gz
pkgsrc_url=http://poc.vl-e.nl/pkgsrc/pkgsrc.tar.gz


# bunch stdout and stderr together
exec 2>&1

# Parse the command-line options. Right now only two options are supported:
# -u update the pkgsrc instance (which is normally skipped because it could take a long time)
# -h print help
# -v explicitly set the VO (normally this is found by inspecting the proxy)

printhelp() {
    cat <<EOF 
usage: pkgsrc-cmd.sh [-u] [-v vo] [-h] <command> [arguments]

Options:
	-u  force update of the pkgsrc installation
	-v  explicitly set VO (use if not recognised automatically)
	-h  print this help
        -d  print debug output

Commands:
      init  Set up pkgsrc for the first time
     check  Check the pkgsrc installation
   install [ pkg ... ] Install the given packages
    remove [ pkg ... ] Remove the given packages
    update [ pkg ... ] Update the given packages
   version  print version information

EOF

}

# should we update pkgsrc itself?
update=0
# what is the VO?
vo=
printhelp=0
debugging=0
bmakedebug=
while getopts udhv: opt; do
    case $opt in
	u)
	    update=1
	    ;;
	v) vo=$OPTARG
	    ;;
	h) printhelp
	    exit 0;
	    ;;
	d) debugging=1 ; bmakedebug="-d cmvx" ;;
	?) printhelp
	    exit 1;
	    ;;
    esac
done
shift $(($OPTIND - 1))

# the debug function prints output if debugging==1
debug() {
    test $debugging -eq 1 && echo debug: "$@" >&2
}

# the log function prints output with a timestamp
log() {
    ts=`date "+%b %e %H:%M:%S %Z"`
    echo "$ts $@"
}

# A similar function to produce an error message and exit
error() {
    log "ERROR: $@"
    exit 1
}

# infer VO from the proxy if not set
if [ -z $vo ]; then
    debug "VO not set, looking at proxy"
    vo=`voms-proxy-info -vo`
    if [ $? -ne 0 ]; then
	error "Could not get VO with voms-proxy-info; try -v <vo>."
    fi
    debug "VO set from proxy: '$vo'"
else
    debug "VO set on command line: '$vo'"
fi

log "Started pkgsrc-cmd.sh. VO=$vo, debugging=$debugging"

# We need an indirection to set the directory of the VO specific software area
vo_sw_dir_var=VO_`echo $vo | tr a-z. A-Z.`_SW_DIR
eval vo_sw_dir=\$$vo_sw_dir_var

debug "VO software area looked for in environment variable: $vo_sw_dir_var"
debug "set vo_sw_dir to $vo_sw_dir"

PKGSRC_LOCATION=$vo_sw_dir/pkgsrc
PKG_PREFIX=$vo_sw_dir/pkg
PATH=$PKG_PREFIX/bin:$PKG_PREFIX/sbin:$PATH
export PATH PKG_PREFIX PKGSRC_LOCATION

debug "PATH set to: $PATH"

log "Running on host: $HOSTNAME"
log "Site name: $SITE_NAME"
log "command: $0 $@"

# This sanity check makes sure we are allowed to write to the software area.
# This check should be done before init, install, delete or any other operation
# that writes data, but not for operations that only read data.
# Also, we need to prevent simultaneous conflicting write operations, so we set
# a lock file at this point. We should remove the lockfile at the end, but
# if that fails we'll check whether it has become 'stale', which means older than
# half an hour.
get_write_lock() {
    log "Checking if the vo software area is writable."
    if [ -z $vo_sw_dir ] ; then
	error "\$$vo_sw_dir_var not set."
    fi

    if [ ! -w $vo_sw_dir ] ; then
	error "\$$vo_sw_dir_var ($vo_sw_dir) is not writable. (Check your proxy: are you the VO software manager?)" 
    fi
    log "$vo_sw_dir writable OK."
    # now do the lockfile shuffle
    lockfile=$vo_sw_dir/pkgsrc-lock
    log "checking lockfile $lockfile"
    if [ -f $lockfile ]; then
	log "lockfile exists."
	ls -l $lockfile
	if [ ! -z `find $lockfile -mmin -30 2> /dev/null` ]; then
	    log "lockfile is still fresh."
	    return 1
	else
	    log "removing stale lockfile (older than 30 minutes)"
	    rm -f $lockfile
	fi
    else
	log "no lockfile found. Setting lock"
    fi
    # At this point, we've concluded we should try and set the lockfile.
    # be careful to avoid race conditions (although rare).
    log "attempting to get lock."
    a=`mktemp $vo_sw_dir/pkgsrc-lock.XXXXXXXXXX` || error "mktemp failed"
    ln $a $lockfile
    if [ $? -ne 0 ]; then
	log "failed to obtain lock"
	rm $a
	return 1
    fi
    log "lock set"
    rm $a
    unset a
    trap "rm -f $lockfile" INT TERM EXIT
    return 0
}

check_installation() {
    debug "Test if $PKGSRC_LOCATION exists"
    if [ ! -d $PKGSRC_LOCATION ]; then
	error "pkgsrc seems not to be installed; run <init> first."
    fi
    for i in pkg_admin pkg_create pkg_info ; do
	if [ ! -x $PKG_PREFIX/sbin/$i ]; then
	    error "$PKG_PREFIX/sbin/$i is missing. Run <init> first."
	fi
    done

    # check the vulnerabilities databases and run an audit
    debug "fetching vulnerabilities and auditing system"
    pkg_admin fetch-pkg-vulnerabilities
    pkg_admin audit
}


# fetch the pkgsrc tarball if necessary
get_pkgsrc() {
    if [ ! -r $PKGSRC_LOCATION/pkgsrc.tar.gz ]; then
	log "$PKGSRC_LOCATION/pkgsrc.tar.gz is not found, downloading for the first time"
    elif [ -z `find $PKGSRC_LOCATION/pkgsrc.tar.gz -mtime -30` ]; then
	log "$PKGSRC_LOCATION/pkgsrc.tar.gz is older than 30 days, fetching new version"
    else
	log "$PKGSRC_LOCATION/pkgsrc.tar.gz is found and fresh."
	ls -l $PKGSRC_LOCATION/pkgsrc.tar.gz
	log "unpacking tarball in `pwd`"
	tar xfz $PKGSRC_LOCATION/pkgsrc.tar.gz
	log "unpacking tarball done."
	return 0
    fi

    # fetch from fast mirror
    log "Fetching pkgsrc.tar.gz from $pkgsrc_url"
    mkdir -p $PKGSRC_LOCATION
    wget --no-verbose -O $PKGSRC_LOCATION/pkgsrc.tar.gz $pkgsrc_url
    if [ $? -ne 0 ]; then
	error "Fetching pkgsrc.tar.gz from $pkgsrc_url failed." 
    fi
    log "$pkgsrc_url saved as $PKGSRC_LOCATION/pkgsrc.tar.gz"
    log "unpacking tarball in `pwd`"
    tar xfz $PKGSRC_LOCATION/pkgsrc.tar.gz
    log "unpacking tarball done."

}


# The command functions. One of these functions will be called from
# the case...esac switch later on.

do_init() {
    log "Starting init."
    get_pkgsrc

    log "Creating temporary work directory for bootstrapping"
    workdir=`mktemp -d -t pkgsrc-bootstrap.XXXXXXXX`/work

    if [ $? -ne 0 ]; then
	error "failed to create temporary working directory"
    fi

    log bootstrapping: pkgsrc/bootstrap/bootstrap --prefix $PKG_PREFIX --unprivileged --workdir $workdir
    pkgsrc/bootstrap/bootstrap --prefix $PKG_PREFIX --unprivileged --workdir $workdir
    if [ $? -ne 0 ]; then
	error "Bootstrapping pkgsrc failed" 
    fi

    # set ALLOW_VULNERABLE_PACKAGES
    tmpcnf=`mktemp`
    sed  '/^.endif/ iALLOW_VULNERABLE_PACKAGES=yes' $PKG_PREFIX/etc/mk.conf > $tmpcnf
    mv $tmpcnf $PKG_PREFIX/etc/mk.conf

    # Make sure that fetching is going to work. The pkgsrc provided tnftp requires
    # libtermcap-devel, which is not commonly found on systems; although pkgsrc also
    # provides ncurses, which could work just fine, fetching the ncurses sources requires
    # tnftp, which means a circular dependency.
    # So we check if the system has wget installed, which is almost always the case, and
    # configure pkgsrc to use wget as an alternative method of fetching sources.
    log "trying to build net/tnftp"
    ( cd pkgsrc/net/tnftp && bmake ${bmakedebug} install && bmake  clean && bmake clean-depends )
    if [ $? -ne 0 ] ; then
	log "failed building net/tnftp."
	log "trying alternatives."
	if [ -x /usr/bin/wget ] ; then
	    log "/usr/bin/wget found. Setting configuration in $PKG_PREFIX/etc/mk.conf"
	    tmpcnf=`mktemp` || exit "failed to create temporary file"
	    sed  '/^.endif/ iPREFER_PKGSRC=termcap\
FETCH_USING= custom\
FETCH_CMD= /usr/bin/wget\
FETCH_BEFORE_ARGS= ${PASSIVE_FETCH:D--passive-ftp}\
FETCH_AFTER_ARGS= # empty\
FETCH_RESUME_ARGS= -c\
FETCH_OUTPUT_ARGS= -O' $PKG_PREFIX/etc/mk.conf > $tmpcnf
	    mv $tmpcnf $PKG_PREFIX/etc/mk.conf
	elif [ -x /usr/bin/curl ] ; then
	    log "/usr/bin/curl found. Setting configuration in $PKG_PREFIX/etc/mk.conf"
	    tmpcnf=`mktemp` || exit "failed to create temporary file"
	    sed  '/^.endif/ iPREFER_PKGSRC=termcap\
FETCH_USING= custom\
FETCH_CMD= /usr/bin/curl
FETCH_BEFORE_ARGS= ${PASSIVE_FETCH:D--ftp-pasv}
FETCH_AFTER_ARGS= -O # must be here to honor -o option
FETCH_RESUME_ARGS= -C -
FETCH_OUTPUT_ARGS= -o' $PKG_PREFIX/etc/mk.conf > $tmpcnf
	    mv $tmpcnf $PKG_PREFIX/etc/mk.conf
	else
	    exit "could not find wget or curl, giving up"
	fi
    else
	log "building net/tnftp succeeded"
    fi

    log "installation OK. Init is done."


}

# In case you ever feel the need to start over, this operation will trash the entire installation
# 
do_clear() {
    log "Starting Clear"
    if [ -f $PKGSRC_LOCATION/pkgsrc.tar.gz ]; then
	log "deleting $PKGSRC_LOCATION/pkgsrc.tar.gz"
	rm -f $PKGSRC_LOCATION/pkgsrc.tar.gz
    fi
    if [ -d $PKG_PREFIX ]; then
	log "Removing $PKG_PREFIX"
	rm -rf $PKG_PREFIX/*
    fi
    log "Done with Clear"
}

do_check() {
    log "Starting check; output goes to status.txt"
    exec 3> status.txt
    {
	echo "Site: $SITE_NAME"
	echo
	echo "Environment:"
	env
	echo
	echo "Installed RPMS:"
	rpm -qa
	echo 
	echo "Our VO: $vo"
	echo "VO Software area set in variable \$$vo_sw_dir_var = $vo_sw_dir"
    } >&3

    if [ -z $vo_sw_dir ] ; then
	echo "\$$vo_sw_dir_var not set. Contact the site administrator."
	# do we need to go on at all at this point?
	echo "It's impossible to install pkgsrc at this site until this is fixed."
	return
    fi
    if [ ! -w $vo_sw_dir ] ; then
	echo "$vo_sw_dir) is not writable, check your proxy (are you the VO software manager?)." 
	ls -ld $vo_sw_dir
	echo "I am: "
	id -a
    fi
    # test the pkgsrc installation
    echo >&3
    echo "Pkgsrc installation" >&3
    echo "PKGSRC_LOCATION=$PKGSRC_LOCATION" >&3
    if [ ! -d $PKGSRC_LOCATION ]; then
	echo "pkgsrc seems not to be installed."
    elif [ ! -f $PKGSRC_LOCATION/pkgsrc.tar.gz ]; then
	echo "$PKGSRC_LOCATION/pkgsrc.tar.gz not found"
    else
	echo "pkgsrc.tar.gz:" >&3
	ls -l $PKGSRC_LOCATION/pkgsrc.tar.gz >&3
    fi
    echo "PKG_PREFIX=$PKG_PREFIX" >&3
    if [ ! -d $PKG_PREFIX ]; then
	echo "$PKG_PREFIX does not exist. Need to bootstrap."
    else
	for i in pkg_admin pkg_create pkg_info ; do
	    filecheck=$PKG_PREFIX/sbin/$i
	    echo -n "Checking for $filecheck..."
	    if [ ! -x $filecheck ]; then
		echo "missing"
	    else
		echo OK
	    fi
	done
    fi
    echo "Configuration: $PKG_PREFIX/etc/mk.conf" >&3
    cat $PKG_PREFIX/etc/mk.conf >&3

    echo "End of Configuration file" >&3

    # check the vulnerabilities databases and run an audit
    log "fetching vulnerabilities and auditing system"
    pkg_admin fetch-pkg-vulnerabilities
    {
	echo "Audit:"
	pkg_admin audit
	echo "End audit:"
	echo
	echo "Installed packages:"
	pkg_info -a
	echo "End of installed packages"
    } >&3

    # if lintpkgsrc is installed, run it.
    if [ -x $PKG_PREFIX/bin/lintpkgsrc ]; then
	debug "running lintpkgsrc -i"
	{
	    echo "lintpkgsrc -i"
	    $PKG_PREFIX/bin/lintpkgsrc -i
	    echo "end of lintpkgsrc"
	    echo
	} >&3
    else
	log "Skipping lintpkgsrc; install pkgtools/lintpkgsrc to include this test"
    fi
    log "Check done."
    return
}

do_install() {
    get_pkgsrc
    # install the packages in $@.
    for i in "$@" ; do
	if [ ! -d pkgsrc/$i ]; then
	    echo "WARNING: unknown package $i" >&2
	    continue
	fi
	( cd pkgsrc/$i && bmake ${bmakedebug} install && bmake  clean && bmake clean-depends )
	if [ $? -ne 0 ] ; then
	    error "bmake failed on $i"
	fi
    done

}

do_remove() {
    check_installation
    # delete the given packages 
    pkg_delete "$@"
}

do_update() {
    get_pkgsrc
    for i in "$@" ; do
	if [ ! -d pkgsrc/$i ]; then
	    echo "WARNING: unknown package $i" >&2
	    continue
	fi
	( cd pkgsrc/$i && bmake update && bmake clean && bmake clean-depends )
    done

}

do_version() {
    log "version() not implemented."
    return 0
}


# all operations need to write to the software area in some way or other, so we
# might as well try to get the write lock here and get it out of the way
get_write_lock || exit 1


# Parse the command-line arguments. Current understood commands are:
# 
# init - set up pkgsrc for the first time
# check - check the pkgsrc setup
# install <packages> - install the given packages
# remove <package> - remove the given packages
# update - update the packages
# version - display version information

if [ $# -gt 0 ] ; then
    case $1 in
	init) do_init ;;
	reinit) do_clear && do_init ;;
	check) do_check ;;
	install) shift; do_install "$@" ;;
	remove) shift; do_remove "$@" ;;
	update) do_update "$@" ;;
	version) do_version ;;
	*)
	    log "ERROR: unknown command given: $1" >&2
	    printhelp
	    exit 1
	    ;;
    esac
    shift
else
    log "No command given. Stop."
    printhelp
    exit 1
fi

log "Script ends."
