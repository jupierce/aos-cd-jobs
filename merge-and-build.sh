#!/bin/bash
# Setup
#set -o xtrace
OSE_MASTER="3.5"
if [ "$#" -ne 2 ]; then
  MAJOR="3"
  MINOR="5"  
  echo "Please pass in MAJOR and MINOR version"
  echo "Using default of ${MAJOR} and ${MINOR}"
else
  MAJOR="$1"
  MINOR="$2"
fi
OSE_VERSION="${MAJOR}.${MINOR}"
if [ "${OSE_VERSION}" == "${OSE_MASTER}" ] ; then
  PUSH_EXTRA="--nolatest"
fi
BUILDPATH="${HOME}/go"
cd $BUILDPATH
export GOPATH=`pwd`
WORKPATH="${BUILDPATH}/src/github.com/openshift/"
echo "GOPATH: ${GOPATH}"
echo "BUILDPATH: ${BUILDPATH}"
echo "WORKPATH ${WORKPATH}"

echo
echo "=========="
echo "Setup origin-web-console stuff"
echo "=========="
cd ${WORKPATH}
rm -rf ose origin origin-web-console
git clone git@github.com:openshift/origin-web-console.git
cd origin-web-console/
git checkout enterprise-${OSE_VERSION}
 if [ "$?" != "0" ]; then exit 1 ; fi
if [ "${OSE_VERSION}" == "${OSE_MASTER}" ] ; then
  git merge master -m "Merge master into enterprise-${OSE_VERSION}"
  git push
fi

echo
echo "=========="
echo "Setup ose stuff"
echo "=========="
cd ${WORKPATH}
git clone git@github.com:openshift/ose.git
cd ose
if [ "${OSE_VERSION}" == "${OSE_MASTER}" ] ; then
  git remote add upstream git@github.com:openshift/origin.git --no-tags
  git fetch --all

  echo
  echo "=========="
  echo "Merge origin into ose stuff"
  echo "=========="
  git merge -m "Merge remote-tracking branch upstream/master" upstream/master
  if [ "$?" != "0" ]; then exit 1 ; fi
else
  git checkout enterprise-${OSE_VERSION}
fi

echo
echo "=========="
echo "Merge in origin-web-console stuff"
echo "=========="
VC_COMMIT="$(GIT_REF=master hack/vendor-console.sh 2>/dev/null | grep "Vendoring origin-web-console" | awk '{print $4}')"
git add pkg/assets/bindata.go
git add pkg/assets/java/bindata.go
git commit -m "Merge remote-tracking branch upstream/master, bump origin-web-console ${VC_COMMIT}"

# Put local rpm testing here

echo
echo "=========="
echo "Tito Tagging"
echo "=========="
tito tag --accept-auto-changelog
  if [ "$?" != "0" ]; then exit 1 ; fi
export VERSION="v$(grep Version: origin.spec | awk '{print $2}')"
echo ${VERSION}
git push
git push --tags

echo
echo "=========="
echo "Tito building in brew"
echo "=========="
TASK_NUMBER=`tito release --yes --test aos-${OSE_VERSION} | grep 'Created task:' | awk '{print $3}'`
echo "TASK NUMBER: ${TASK_NUMBER}"
brew watch-task ${TASK_NUMBER}
  if [ "$?" != "0" ]; then exit 1 ; fi

echo
echo "=========="
echo "Building Puddle"
echo "=========="
ssh tdawson@rcm-guest.app.eng.bos.redhat.com "puddle -b -d /mnt/rcm-guest/puddles/RHAOS/conf/atomic_openshift-${OSE_VERSION}.conf -n -s --label=building"

echo
echo "=========="
echo "Update Dockerfiles to new version"
echo "=========="
ose_images.sh update_docker --branch rhaos-${OSE_VERSION}-rhel-7 --group base --force --release 1 --version ${VERSION}
   if [ "$?" != "0" ]; then exit 1 ; fi

echo
echo "=========="
echo "Build Images"
echo "=========="
ose_images.sh build_container --branch rhaos-${OSE_VERSION}-rhel-7 --group base --repo http://file.rdu.redhat.com/tdawson/repo/aos-unsigned-building.repo
   if [ "$?" != "0" ]; then exit 1 ; fi

echo
echo "=========="
echo "Push Images"
echo "=========="
sudo ose_images.sh push_images ${PUSH_EXTRA} --branch rhaos-${OSE_VERSION}-rhel-7 --group base
   if [ "$?" != "0" ]; then exit 1 ; fi

echo
echo "=========="
echo "Create latest puddle"
echo "=========="
ssh tdawson@rcm-guest.app.eng.bos.redhat.com "puddle -b -d /mnt/rcm-guest/puddles/RHAOS/conf/atomic_openshift-${OSE_VERSION}.conf"

echo
echo "=========="
echo "Sync latest puddle to mirrors"
echo "=========="
echo "Not run due to permission problems"
#ssh user@rcm-guest.app.eng.bos.redhat.com " /mnt/rcm-guest/puddles/RHAOS/scripts/push-to-mirrors.sh simple ${OSE_VERSION}"

echo
echo
echo "=========="
echo "Finished"
echo "OCP ${VERSION}"
echo "=========="
