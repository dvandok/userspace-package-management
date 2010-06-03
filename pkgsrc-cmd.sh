#!/bin/sh

umask 002

# should we update pkgsrc itself?
update=0
# what is the VO?
vo=
while getopts uv: opt; do
    case $opt in
	u)
	    update=1
	    ;;
	v) vo=$OPTARG
    esac
done
shift $(($OPTIND - 1))

# infer VO from the proxy if not set

if [ -n $vo ]; then
    vo=`voms-proxy-info -vo`
    if [ $? -ne 0 ]; then
	echo "Could not get VO with voms-proxy-info; try -v <vo>." >&2
	exit 1
    fi
fi

vo_sw_dir_var=VO_`echo $vo | tr a-z. A-Z.`_SW_DIR
eval vo_sw_dir=\$$vo_sw_dir_var

# sanity check

if [ -z $vo_sw_dir ] ; then
    echo "\$$vo_sw_dir_var not set, abandoning run." >&2
    exit 1
fi


if [ ! -w $vo_sw_dir ] ; then
    echo "\$vo_sw_dir ($vo_sw_dir) is not writable, check your proxy (are you the VO software manager?)." >&2
    exit 1
fi

PKGSRC_LOCATION=$vo_sw_dir/pkgsrc
PKG_PREFIX=$vo_sw_dir/pkg
PATH=$PKG_PREFIX/bin:$PKG_PREFIX/sbin:$PATH
export PATH



# install pkgsrc

cd $vo_sw_dir

if [ -d pkgsrc ]; then
    echo "pkgsrc is already installed"
    cd pkgsrc
    ### possibly do a system update at this point
    if [ $update -eq 1 ] ; then
	umask 022
	test -d $HOME/.ssh || mkdir $HOME/.ssh
	if [ -n `ssh-keygen -F anoncvs.netbsd.org` ] ; then
	    cat >> $HOME/.ssh/known_hosts <<EOF
# anoncvs.netbsd.org SSH-2.0-OpenSSH_5.0 NetBSD_Secure_Shell-20080403-hpn13v1
anoncvs.netbsd.org ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAIEA3QiBl8leG9fqIJpKeNov0PKq5YryFFiroMWOPUv4hDFn8R0jC07YVaR/OSBrr37CTmGX5AFceXPzoFnLlwCqWR7rXg4NR75FTlTp9CG9EBAEtU8mee27KDrUFBTZdfVl2+aRYoAI5fTXA+0vpIO68Cq843vRWUZCcwinS4cNLUU=
EOF
	fi
	CVS_RSH=ssh cvs update -dP
    fi

else
    # fetch from fast mirror
    wget -O pkgsrc.tar.gz ftp://ftp.nl.netbsd.org/pub/NetBSD/packages/pkgsrc.tar.gz

    tar xfz pkgsrc.tar.gz

    cd pkgsrc
    
    workdir=`mktemp -d -t pkgsrc-bootstrap.XXXXXXXX`/work

    if [ $? -ne 0 ]; then
	echo "failed to create temporary working directory" >&2
	exit 1
    fi

    ./bootstrap/bootstrap --prefix $PKG_PREFIX --unprivileged --workdir $workdir

    if [ $? -ne 0 ]; then
	echo "Bootstrapping pkgsrc failed" >&2
	exit 1
    fi

    echo "installation OK"

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
