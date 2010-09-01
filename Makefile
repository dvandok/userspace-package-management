files-to-sync = pkgsrc-cmd.sh get-site-status.sh site-pkg-install.sh

files-to-package = $(files-to-sync) notes.org fetch-update.sh 

package = userspace-package-management.tar.gz

sync:
	scp  $(files-to-sync) bosui.nikhef.nl:
	scp $(files-to-sync) pocui.testbed:


dist:
	tar cfz $(package) $(files-to-package)

perms:
	chmod +x *.sh
