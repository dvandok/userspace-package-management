#!/bin/sh

# This is to be run from a daily cron job.
pkgsrcurl=ftp://ftp.nl.netbsd.org/pub/NetBSD/packages/pkgsrc.tar.gz
tmpdir=`mktemp -d` || { echo "failed to create tmp dir" ; exit 1; }
cd $tmpdir
wget -O pkgsrc.tar.gz $pkgsrcurl
if [ $? -ne 0 ]; then
    echo "failed to fetch $pkgsrcurl"
    exit 1
fi

#unpack, update and repack
tar xfz pkgsrc.tar.gz
(cd pkgsrc && cvs update -dP)
tar cfz pkgsrc.tar.gz pkgsrc

# upload to public space; this cannot be done in a cron job!
#scp pkgsrc.tar.gz poc.vl-e.nl:wwwpoc/html/pkgsrc/pkgsrc.tar.gz

# return to home directory and cleanup temporary
cd
rm -r $tmpdir
