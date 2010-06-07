#!/bin/sh

# The umask setting makes everything we do group writable, which is a requirement for stuff
# we leave in the VO software area. If we didn't, only the original user would be able to
# modify or remove these files.
umask 002

# This is the location to fetch pkgsrc.tar.gz from. It's a fast mirror.
pkgsrc_url=ftp://ftp.nl.netbsd.org/pub/NetBSD/packages/pkgsrc.tar.gz

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
while getopts uhv: opt; do
    case $opt in
	u)
	    update=1
	    ;;
	v) vo=$OPTARG
	    ;;
	h) printhelp
	    exit 0;
	    ;;
	d debugging=1 ;;
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

# A similar function to produce an error message and exit
error() {
    echo "ERROR: $@" >&2
    exit 1
}

# infer VO from the proxy if not set
if [ -n $vo ]; then
    debug "VO not set, looking at proxy"
    vo=`voms-proxy-info -vo`
    if [ $? -ne 0 ]; then
	error "Could not get VO with voms-proxy-info; try -v <vo>."
    fi
    debug "VO set from proxy: '$vo'"
else
    debug "VO set on command line: '$vo'"
fi


# We need an indirection to set the directory of the VO specific software area
vo_sw_dir_var=VO_`echo $vo | tr a-z. A-Z.`_SW_DIR
eval vo_sw_dir=\$$vo_sw_dir_var

debug "VO software area looked for in environment variable: $vo_sw_dir_var"
debug "set vo_sw_dir to $vo_sw_dir"

PKGSRC_LOCATION=$vo_sw_dir/pkgsrc
PKG_PREFIX=$vo_sw_dir/pkg
PATH=$PKG_PREFIX/bin:$PKG_PREFIX/sbin:$PATH
export PATH

debug "PATH set to: $PATH"

# This sanity check makes sure we are allowed to write to the software area.
# This check should move to cover only the activities that really mean to write
# things, such as install or update.
check_writable_sw_area() {
    if [ -z $vo_sw_dir ] ; then
	error "\$$vo_sw_dir_var not set."
    fi

    if [ ! -w $vo_sw_dir ] ; then
	error "\$$vo_sw_dir_var ($vo_sw_dir) is not writable, check your proxy (are you the VO software manager?)." 
    fi
}

check_installation() {
    debug "Test if $PKGSRC_LOCATION exists"
    if [ ! -d $PKGSRC_LOCATION ]; then
	error "pkgsrc seems not to be installed; run <init> first."
    fi
    return 0
}

# make sure CVS calls to the anonymous NetBSD cvs server will work
# only when -u is given on command-line
setup_cvsssh() {
    check_writable_sw_area
    if [ update -eq 0 ]; then
	debug "Skip update from CVS (use -u to trigger update)"
	return 1
    fi
    debug "setting up .ssh/known_hosts to allow CVS connection to anoncvs.netbsd.org"
    umask 022
    test -d $HOME/.ssh || mkdir $HOME/.ssh
    if [ -n `ssh-keygen -F anoncvs.netbsd.org` ] ; then
	cat >> $HOME/.ssh/known_hosts <<EOF
# anoncvs.netbsd.org SSH-2.0-OpenSSH_5.0 NetBSD_Secure_Shell-20080403-hpn13v1
anoncvs.netbsd.org ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAIEA3QiBl8leG9fqIJpKeNov0PKq5YryFFiroMWOPUv4hDFn8R0jC07YVaR/OSBrr37CTmGX5AFceXPzoFnLlwCqWR7rXg4NR75FTlTp9CG9EBAEtU8mee27KDrUFBTZdfVl2+aRYoAI5fTXA+0vpIO68Cq843vRWUZCcwinS4cNLUU=
EOF
	debug "hostkey for anoncvs.netbsd.org added"
    fi
    umask 002
}

cvs_update() {
    check_installation
    setup_cvsssh
    debug "doing cvs update in $PKGSRC_LOCATION"
    (cd  $PKGSRC_LOCATION && CVS_RSH=ssh cvs update -dP )
}



# The command functions. One of these functions will be called from
# the case...esac switch later on.

do_init() {
    check_writable_sw_area

    if [ -d $PKGSRC_LOCATION ]; then
	echo "pkgsrc seems to be already installed"
	
	# need to do more checks here?
	return

    fi
    # fetch from fast mirror
    wget -O pkgsrc.tar.gz $pkgsrc_url
    if [ $? -ne 0 ]; then
	error "Fetching pkgsrc.tar.gz from $pkgsrc_url failed." 
    fi
    tar xCfz $vo_sw_dir pkgsrc.tar.gz

    workdir=`mktemp -d -t pkgsrc-bootstrap.XXXXXXXX`/work

    if [ $? -ne 0 ]; then
	error "failed to create temporary working directory"
    fi

    $PKGSRC_LOCATION/bootstrap/bootstrap --prefix $PKG_PREFIX --unprivileged --workdir $workdir

    if [ $? -ne 0 ]; then
	error "Bootstrapping pkgsrc failed" 
    fi

    echo "installation OK"


}

do_check() {

    echo "================================== Environment ===================================="
    env
    echo "================================= /Environment ===================================="
    echo
    # test the pkgsrc installation
    check_installation
    echo "================================= Installed packages =============================="
    pkg_info
    echo "================================ /Installed packages =============================="
    # if lintpkgsrc is installed, run it.
    if [ -x $PKG_PREFIX/bin/lintpkgsrc ]; then
	debug "running lintpkgsrc -i"
	echo "==================== lintpkgsrc -i ===================="
	$PKG_PREFIX/bin/lintpkgsrc -i
    else
	echo "Skipping lintpkgsrc; install pkgtools/lintpkgsrc to include this test"
    fi
    return
}

do_install() {
    cvs_update
    # install the packages in $@.
    for i in "$@" ; do
	if [ ! -d $PKGSRC_LOCATION/$i ]; then
	    echo "WARNING: unknown package $i" >&2
	    continue
	fi
	( cd $PKGSRC_LOCATION/$i && bmake install && bmake clean && bmake clean-depends )
    done

}

do_remove() {
    check_writable_sw_area
    check_installation
    # delete the given packages 
    pkg_delete "$@"
}

do_update() {
    cvs_update
    for i in "$@" ; do
	if [ ! -d $PKGSRC_LOCATION/$i ]; then
	    echo "WARNING: unknown package $i" >&2
	    continue
	fi
	( cd $PKGSRC_LOCATION/$i && bmake update && bmake clean && bmake clean-depends )
    done

}

do_version() {
    cvs_update
    (cd $PKGSRC_LOCATION && cvs  status -v README)
}



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
	check) do_check ;;
	install) shift; do_install "$@" ;;
	remove) shift; do_remove "$@" ;;
	update) do_update "$@" ;;
	version) do_version ;;
	*)
	    echo "ERROR: unknown command $1" >&2
	    printusage
	    exit 1
	    ;;
    esac
    shift
else
    echo "No command given."
    printhelp
    exit 1
fi






pkg_admin fetch-pkg-vulnerabilities
pkg_admin audit

# Any remaining arguments on the commandline are taken as a literal command to execute

if [ $# -ge 1 ]; then
    echo "executing $@"
    eval "$@"
else
    exit 0
fi
