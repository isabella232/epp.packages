#!/bin/bash

set -u # run with unset flag error so that missing parameters cause build failure
set -e # error out on any failed commands
set -x # echo all commands used for debugging purposes

EXITCODE=0 # default to 0, set to 124 to mark unstable or anything else for failure

SSHUSER="genie.packaging@projects-storage.eclipse.org"
SSH="ssh ${SSHUSER}"
SCP="scp"

RELEASE_NAME=2021-03
RELEASE_MILESTONE=R
WORKSPACE=${WORKSPACE:-"${PWD}"}
GIT_REPOSITORY=${GIT_REPOSITORY:-"org.eclipse.epp.packages"}
BUILT_PACKAGES=$(cat packages.txt)
PACKAGES=${BUILT_PACKAGES:-"committers cpp dsl embedcpp java jee modeling parallel php rcp scout"}
PLATFORMS=${PLATFORMS:-"linux.gtk.aarch64.tar.gz linux.gtk.x86_64.tar.gz macosx.cocoa.x86_64.dmg macosx.cocoa.x86_64.tar.gz win32.win32.x86_64.zip"}
STAGING=${STAGING:-"/home/data/httpd/download.eclipse.org/technology/epp/staging"}

cd ${WORKSPACE}/${GIT_REPOSITORY}/archive
for PACKAGE in $PACKAGES; do
  for PLATFORM in $PLATFORMS; do
    NAME=$(echo *_eclipse-${PACKAGE}-${RELEASE_NAME}-${RELEASE_MILESTONE}-${PLATFORM})
    NEWNAME=`echo ${NAME} | \
             cut -d "_" -f 2- | \
             sed 's/linux\.gtk\.aarch64/linux-gtk-aarch64/' | \
             sed 's/linux\.gtk\.x86\_64/linux-gtk-x86\_64/' | \
             sed 's/win32\.win32\.x86\_64\./win32\-x86\_64\./' | \
             sed 's/macosx\.cocoa\.x86\_64/macosx\-cocoa-x86\_64/' | \
             sed 's/macosx-cocoa-x86_64.dmg/macosx-cocoa-x86_64.dmg-tonotarize/'`
    # Move and rename file
    mv ${NAME} ${NEWNAME}
  done;
done

# place configurations in final location
for PACKAGE in $PACKAGES; do
  cp ${WORKSPACE}/${GIT_REPOSITORY}/packages/org.eclipse.epp.package.${PACKAGE}.feature/epp.website.xml ${PACKAGE}.xml
  cp ${WORKSPACE}/${GIT_REPOSITORY}/packages/org.eclipse.epp.package.${PACKAGE}.feature/feature.xml ${PACKAGE}.feature.xml
  cp ${WORKSPACE}/${GIT_REPOSITORY}/packages/org.eclipse.epp.package.${PACKAGE}.product/epp.product ${PACKAGE}.product.xml
done

# place a timestamp and CI build info in the directory
echo "TIMESTAMP: $(date)" > ci-info.txt
echo "CI URL: ${BUILD_URL}" >> ci-info.txt

# -----------------------------
# Notarize macos files

# cd ${WORKSPACE}
# for i in $(find ${WORKSPACE}/${GIT_REPOSITORY}/archive -name '*.dmg-tonotarize')
# do
#    DMG_FILE=${i/-tonotarize/}
#    LOG=$(basename ${i}).log
#    echo "Starting ${DMG_FILE}" >> ${WORKSPACE}/${LOG}
#    ${WORKSPACE}/${GIT_REPOSITORY}/releng/org.eclipse.epp.config/tools/macosx-notarization-single.sh ${DMG_FILE} >> ${LOG} &
#    sleep 18s # start jobs at a small interval from each other
# done

# jobs -p
# wait < <(jobs -p)


# if [[ -n `find ${WORKSPACE}/${GIT_REPOSITORY}/archive -name '*.dmg-tonotarize'` ]]; then
#    echo "Failed to notarize the following"
#    find ${WORKSPACE}/${GIT_REPOSITORY}/archive -name '*.dmg-tonotarize'
#    # unstable - we don't want to fail the build for failed notarize because
#    # the notarization is just too flaky and we can renotarize any missed
#    # files later
#    EXITCODE=124 
# fi
# cd ${WORKSPACE}/${GIT_REPOSITORY}/archive


# ----------------------------------------------------------------------------------------------
# compute the checksum files for each package

for II in $(find eclipse*.zip eclipse*.tar.gz eclipse*.dmg eclipse*.dmg-tonotarize); do
  echo .. $II
  md5sum $II >$II.md5
  sha1sum $II >$II.sha1
  sha512sum -b $II >$II.sha512
done

# ----------------------------------------------------------------------------------------------
# Copy everything to download.eclipse.org

${SSH} rm -rf ${STAGING}-new
${SCP} -rp . "${SSHUSER}:"${STAGING}-new
${SSH} rm -rf ${STAGING}-previous
if $SSH test -e ${STAGING}; then
  ${SSH} mv ${STAGING} ${STAGING}-previous
fi
${SSH} mv ${STAGING}-new ${STAGING}
${SSH} rm -rf ${STAGING}-previous

# Explicitly exit so that we can mark as unstable more easily
exit ${EXITCODE}
