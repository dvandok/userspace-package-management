#!/bin/sh

# Install software at a given site, using pkgsrc-cmd.

# Site is first argument
# the software is the remainder
delegation=dennis

site=$1

shift

resource=`awk '$1='$site' { print $2 }`

if [ -z $resource ] ; then
    echo "Resource for site '$site' not found in resources.dat" > /dev/stderr
    exit 1
fi


if [ $# -lt 1 ] ; then
    echo "Usage: $0 <site> package [ package ... ]" > /dev/stderr
    exit 1
fi

jdl=`mktemp site-install.jdl-XXXXXXXXXX`
cat > $jdl <<EOF
Executable = "pkgsrc-cmd.sh";
Arguments = "install $@";
Stdoutput = "stdout";
StdError = "stderror";
InputSandbox = "../pkgsrc-cmd.sh";
OutputSandbox = {"stdout","stderror"};
EOF

glite-wms-job-submit -d $delegation -o jids -r $resource $jdl
if [ $? -ne 0 ]; then
    echo "Failed to submit job $jdl to $resource" > /dev/stderr
    exit 1
fi

echo "Job submitted; check back later for results."

exit 0

