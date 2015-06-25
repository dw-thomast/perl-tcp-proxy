#!/bin/sh

APPNAME="tcp-proxy"
STRIP="ppi" #ppi"
LINKTYPE="static" #allow-dynamic"
RC_FILE=${HOME}/.staticperlrc
SP_FILE=${HOME}/staticperl
BOOT_FILE="tcp-proxy.pl"
ARCH=$(uname -m)

if [ -f ${RC_FILE} ]; then
        . ${RC_FILE}
else
        echo "${RC_FILE}: not found"
        exit 1
fi

${SP_FILE} perl -c tcp-proxy.pl || exit 1

${SP_FILE} mkapp $APPNAME --boot ${BOOT_FILE} \
-MGetopt::Long \
-MIO::Socket \
-MIO::Select \
--strip ${STRIP} \
--${LINKTYPE} \
--usepacklists \
$@

upx -9 ${APPNAME}
mv ${APPNAME} bin/${APPNAME}_${ARCH:-unknown}
