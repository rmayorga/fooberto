#!/bin/sh

[ ! -d debian-packages ] && mkdir debian-packages

echo "uptating unstable packages files...."
wget --quiet http://ftp.us.debian.org/debian/dists/unstable/main/binary-i386/Packages.gz -O debian-packages/main-unstable.gz
wget --quiet  http://ftp.us.debian.org/debian/dists/unstable/contrib/binary-i386/Packages.gz -O debian-packages/contrib-unstable.gz
wget --quiet http://ftp.us.debian.org/debian/dists/unstable/non-free/binary-i386/Packages.gz -O debian-packages/nonfree-unstable.gz

echo "done."

echo "uptating testing packages files...."
wget --quiet http://ftp.us.debian.org/debian/dists/testing/main/binary-i386/Packages.gz -O debian-packages/main-testing.gz
wget --quiet  http://ftp.us.debian.org/debian/dists/testing/contrib/binary-i386/Packages.gz -O debian-packages/contrib-testing.gz
wget --quiet http://ftp.us.debian.org/debian/dists/testing/non-free/binary-i386/Packages.gz -O debian-packages/nonfree-testing.gz

echo "done"

echo "uptating stable packages files...."
wget --quiet http://ftp.us.debian.org/debian/dists/stable/main/binary-i386/Packages.gz -O debian-packages/main-stable.gz
wget --quiet  http://ftp.us.debian.org/debian/dists/stable/contrib/binary-i386/Packages.gz -O debian-packages/contrib-stable.gz
wget --quiet http://ftp.us.debian.org/debian/dists/stable/non-free/binary-i386/Packages.gz -O debian-packages/nonfree-stable.gz

echo "done"
