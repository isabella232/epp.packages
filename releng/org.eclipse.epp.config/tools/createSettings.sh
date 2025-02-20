#!/bin/bash
#
#  Copyright (c) 2014, 2021 Innoopract Informationssysteme GmbH and others.
#  All rights reserved. This program and the accompanying materials
#  are made available under the terms of the Eclipse Public License v2.0
#  which accompanies this distribution, and is available at
#  http://www.eclipse.org/legal/epl-v20.html
# 
#  Contributors:
#     Innoopract Informationssysteme GmbH - initial API and implementation
#     EclipseSource - ongoing development
###############################################################################

###############################################################################
# The purpose of this little shell script is to generate a settings.xml
# for Maven that contains a list of packages (as activated profiles) based
# on the last commit to Git. The idea is that this helps to reduce the
# number of CPU cycles that are required in a Gerrit verification build job
# by building only the relevant packages. 
# (Relevant == the packages that are potentially affected by this change)
###############################################################################

WORKSPACE=${WORKSPACE:-"${PWD}"}
GIT_REPOSITORY=${GIT_REPOSITORY:-"org.eclipse.epp.packages"}
SETTINGS_FILE=${SETTINGS_FILE:-"${WORKSPACE}/settings.xml"}
PACKAGE_LIST=${PACKAGE_LIST:-"${WORKSPACE}/packages.txt"}
IGNORED_PACKAGES=${IGNORED_PACKAGES:-""}
FULL_BUILD=${FULL_BUILD:-"false"}

echo "Creating ${SETTINGS_FILE}"
echo "Ignoring package(s): ${IGNORED_PACKAGES}"


echo "Creating list of built packages"
rm -f $PACKAGE_LIST


### add initial content (proxy definition) from $HOME/.m2/settings.xml
echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" >$SETTINGS_FILE
echo "<settings xmlns=\"http://maven.apache.org/SETTINGS/1.0.0\"" >>$SETTINGS_FILE
echo "          xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"" >>$SETTINGS_FILE
echo "          xsi:schemaLocation=\"http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd\">" >>$SETTINGS_FILE
echo "" >>$SETTINGS_FILE
echo "  <mirrors>" >>$SETTINGS_FILE
echo "    <mirror>" >>$SETTINGS_FILE
echo "      <id>eclipse.maven.central.mirror</id>" >>$SETTINGS_FILE
echo "      <name>Eclipse Central Proxy</name>" >>$SETTINGS_FILE
echo "      <url>https://repo.eclipse.org/content/repositories/maven_central/</url>" >>$SETTINGS_FILE
echo "      <mirrorOf>central</mirrorOf>" >>$SETTINGS_FILE
echo "    </mirror>" >>$SETTINGS_FILE
echo "  </mirrors>" >>$SETTINGS_FILE

echo "  <activeProfiles>" >>$SETTINGS_FILE

## PACKAGES contains the list of packages that have been examined already. Start
## by preloading with IGNORED_PACKAGES so that none of them are added
PACKAGES="xxx ${IGNORED_PACKAGES} xxx"


### use the HEAD commit to find out which package directories contain a change
### XXX: This code adds packages to the profile that were edited in the HEAD commit. However this code doesn't
### cope with a package being removed, as happened in Bug 570821. Rather than fix this for the rare removal
### of packages, simply adjust the build by having a new HEAD or changing the CI build parameters to ignore
### the deleted package.
cd ${WORKSPACE}/${GIT_REPOSITORY}
for II in `git diff-tree --name-only --no-commit-id -r HEAD | cut -d "/" -f 2 | cut -d "." -f 5 | sort | uniq`; do
  if [[ "common" == ${II} ]]
  then
    echo "Change detected in common bundles found; will trigger a full package build."
    FULL_BUILD="true"
    continue
  fi
  if [[ ${IGNORED_PACKAGES} =~ ${II} ]]
  then
    echo "${II} contains changes, but is ignored or already added."
    continue
  fi
  PACKAGE="epp.package.${II}"
  echo "Adding package $PACKAGE"
  echo "${II}" >>$PACKAGE_LIST
  echo "    <activeProfile>${PACKAGE}</activeProfile>" >>$SETTINGS_FILE
  PACKAGES="${PACKAGES} ${PACKAGE}"
done
cd ${WORKSPACE}

### if there are changes in other areas of the Git repo then build everything
cd ${WORKSPACE}/${GIT_REPOSITORY}
OTHERCHANGES="xxx`git diff-tree --name-only --no-commit-id -r HEAD | grep -v "^packages"`xxx"
if [ "${OTHERCHANGES}" != "xxxxxx" ] || [ "${FULL_BUILD}" == "true" ]
then
  echo "Full build required. Adding all packages"
  ALLPACKAGES="xxx `ls packages | cut -d "." -f 5 | sort | uniq` xxx"
  for II in ${ALLPACKAGES}; do
    if [[ "xxx" == ${II} ]]
    then
      continue
    fi
    if [[ "common" == ${II} ]]
    then
      continue
    fi
    if [[ ${PACKAGES} =~ "epp.package.${II}" ]]
    then
      echo "${II} should be added for all packages, but it is ignored or already added."
      continue
    elif [[ ${PACKAGES} =~ " ${II} " ]]
    then
      echo "${II} should be added for all packages, but it is ignored or already added."
      continue
    else
      PACKAGE="epp.package.${II}"
      echo "Adding package $PACKAGE"
      echo "${II}" >>$PACKAGE_LIST
      echo "    <activeProfile>${PACKAGE}</activeProfile>" >>$SETTINGS_FILE
      PACKAGES="${PACKAGES} ${PACKAGE}"
    fi
  done
fi
cd ${WORKSPACE}

# This is a kludge - we want to run this all the time, unless we are building
# only packages that don't contain justj. Therefore we do this all the time,
# unless a single package is being built.
if [[ $(cat $PACKAGE_LIST | wc -l) == 1 ]]; then
  echo "Will not run remove-justj-from-p2 profile"
else
  echo "Will run remove-justj-from-p2 profile"
  echo "    <activeProfile>remove-justj-from-p2</activeProfile>" >>$SETTINGS_FILE
fi

### close the settings.xml file
echo "  </activeProfiles>" >>$SETTINGS_FILE
echo "" >>$SETTINGS_FILE
echo "</settings>" >>$SETTINGS_FILE

echo "Written new $SETTINGS_FILE"

