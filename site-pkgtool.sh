#!/bin/sh

# Install software at a given site, using pkgsrc-cmd.

# Site is first argument
# the software is the remainder

#
function usage {
	echo "Usage: $0 <site> <install | remove | update> [ package ... ]" > /dev/stderr
	echo "       $0 <site> <init | reinit | check | dump | info | version>" > /dev/stderr
}

JIDS=site-pkgtool.jids

site=$1
shift

if [ -z "$site" ]; then
	usage
	exit 1
fi

resource=`awk '$1=="'$site'" { print $2 }' etc/resources.dat`

if [ -z "$resource" ]; then
	echo "Site '$site' not found in etc/resources.dat." > /dev/stderr
	usage
	exit 1
fi

if [ $# -gt 0 ]; then
    case $1 in
        init | reinit | check | dump | info | version)
		command=$1
    		shift
		if [ $# -gt 0 ]; then
			usage;
			exit 1
		fi
		;;
        install | remove | update)
		command=$1
    		shift
		if [ $# -le 0 ]; then
			echo "No package(s) given."
			usage;
			exit 1
		fi
		;;
        *)
		echo "Unknown command given."
	    usage;
            exit 1
            ;;
    esac
else
	echo "No command given."
	usage
	exit 1
fi

jdl=`mktemp site-pkg.jdl-XXXXXXXXXX`
cat > $jdl <<EOF
Executable = "pkgsrc-cmd.sh";
Arguments = "$command $@";
Stdoutput = "stdout";
StdError = "stderror";
InputSandbox = "pkgsrc-cmd.sh";
OutputSandbox = {"stdout","stderror"};
PerusalFileEnable = true;
PerusalTimeInterval = 60;
EOF

glite-wms-job-submit -d $USER -o $JIDS -r $resource $jdl
if [ $? -ne 0 ]; then
    echo "Failed to submit job $jdl to $resource" > /dev/stderr
    exit 1
fi

# enabling perusal for stdout and stderr
glite-wms-job-perusal --set -f stdout -f stderror `tail -1 $JIDS`
echo "Job submitted; check back later for results."

rm $jdl
exit 0
