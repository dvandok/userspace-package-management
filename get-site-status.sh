#!/bin/bash

# FIXMELATER
delegation=dennis

# look up the resources in the data file

sites=`awk ' $1 !~ /^#/ { print $1 }'` resources.dat

for i in $sites ; do
    # create a work directory
    workdir=$i
    if [ ! -d $workdir ]; then
	mkdir $workdir
    fi
    ( cd $workdir
	endpoint=`awk "\$1 == $i { print \$2 }"`
	jobfile=pkgsrc-status.jdl
	cat > $jobfile <<EOF
Executable = "pkgsrc-cmd.sh";
Arguments = "-d check";
Stdoutput = "stdout";
StdError = "stderror";
InputSandbox = "../pkgsrc-cmd.sh";
OutputSandbox = {"stdout","stderror"};
EOF
	glite-wms-job-submit -d $delegation -o jids -r $endpoint $jobfile
	if [ $? -ne 0 ]; then
	    echo "Error: Failed to submit job to $i" >&2
	fi
    ) &

done

# wait and poll; systematically go through all the jid files and check their
# status. When a job has finished, fetch the results and clean up.

# $1 is job id
get_job_output() {
    jobhash=`echo $1 | sed -e 's,.*/,,'`

#    mkdir $jobdir || die "can't mkdir $jobdir"
    glite-wms-job-output --noint --dir $jobhash $1
    if [ $? -ne 0 ] ; then
	echo "failed to get job output for $1" >&2
	echo "job output retrieval failure" >&3
	return 1
    fi
    # just append
    cat $jobhash/stdout >> status
    cat $jobhash/stderr >> error-log
    rm -rf $jobhash
}

# $1 = jobid $2 = state
get_logging_and_clear() {
    # get the logging info for the job ...
    echo "job $1 is $2, getting logging and removing it"
    glite-wms-job-logging-info -o joblog-$jobhash.log \
	--noint -v 3 $1
    # ... then remove the jobid from the list.
    grep -v -F "$1" jids > jids.new && mv jids.new jids
}

waitlonger=1

while [ $waitlonger -eq 1 ]; do
    waitlonger=0
    for i in $sites ; do
	( 
	    cd $i
	    if test -f jids && grep -q '^https:' jids; then
		jobs=`grep -v '^#' jids`
		for j in $jobs ; do
		    jobhash=`echo $j | sed -e 's,.*/,,'`
		    rm -f jobstate
		    glite-wms-job-status --noint -o jobstate $j
                        # grep the status file for "Current Status"
		    state=`sed -n -e '/Current Status/  s/.*:\s*// p' jobstate`
		    case $state in
			"Done"* )
			# job is done, get the output
			    echo "job $j is done, getting output"
			    get_job_output $j
			    get_logging_and_clear $j $state
			    ;;
			Cleared* | Aborted* | Cancelled* ) 
			    get_logging_and_clear $j $state
			    ;;
			* )
		             # job still in queue.
			    waitlonger=1
			    ;;
		    esac
		    done
	    fi
	) &
    done

done

# fetch results, interpret and publish

