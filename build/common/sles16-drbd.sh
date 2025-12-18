#!/bin/bash

echo "DRBD Build"

PATH=$PATH:/usr/local/bin:/usr/local/sbin
export PATH

zypper --non-interactive --gpg-auto-import-keys install \
  gcc glibc-devel linux-glibc-devel git \
  kernel-default kernel-devel \
  make perl rpm-build tar wget flex bison \
  libxml2-devel libxslt-devel \
  keyutils-devel po4a

# kernel module
DRBD=drbd-9.2.16
DRBDTAR=${DRBD}.tar.gz

wget https://pkg.linbit.com//downloads/drbd/9/${DRBDTAR}
tar xzf ${DRBDTAR}
cd ${DRBD}

make -j"$(nproc)"
make install

echo "Running depmod"
depmod -a "$(uname -r)"

echo "Verifying kernel module"
modinfo drbd | grep '^version'

cd

RUBY_DOC_PKG="ruby2.5-rubygem-asciidoctor"
grep -q '12-' /etc/os-release && RUBY_DOC_PKG="ruby2.1-rubygem-asciidoctor"

# drbd tools
zypper --non-interactive --gpg-auto-import-keys install \
  $RUBY_DOC_PKG flex keyutils-devel

DRBDUTILS=drbd-utils-9.33.0
DRBDUTILSTAR=${DRBDUTILS}.tar.gz

wget https://pkg.linbit.com//downloads/drbd/utils/${DRBDUTILSTAR}
tar xzf ${DRBDUTILSTAR}
cd ${DRBDUTILS}

./autogen.sh
./configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc
make tools install-tools

cd
rm -rf drbd* coccinelle

exit 0

