#!/bin/sh
#
# This script assumes there is a "pkgsrc" directory which holds the whole tree.
# 
# It will create a new tarball out of the tree and copies the file to the website.
# If run with -u, it will also cvs update the tree before creating the tarball.
#

if [ "$1" = "-u" ]; then
	echo "CVS update the pkgsrc tree ..."
	(cd pkgsrc && cvs update -dP)
fi

echo "Creating tarball ..."
tar -czf pkgsrc.tar.gz pkgsrc

echo "Copying tarball to website ..."
mv pkgsrc.tar.gz /var/www/html/pkgsrc/
