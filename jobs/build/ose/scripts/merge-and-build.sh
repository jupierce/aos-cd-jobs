#!/bin/bash

## This script must run with an ssh key for openshift-bot loaded.
export PS4='${LINENO}: '
set -o xtrace

set -o errexit
set -o nounset
set -o pipefail

function get_version_fields {
    COUNT="$1"

    if [ "$COUNT" == "" ]; then
        echo "Invalid number of Version fields specified: $COUNT"
        return 1
    fi

    V="$(grep Version: origin.spec | awk '{print $2}')"
    # e.g. "3.6.126" => "3 6 126" => wc + awk gives number of independent fields
    export CURRENT_COUNT="$(echo ${V} | tr . ' ' | wc | awk '{print $2}')"

    # If there are more fields than we expect, something has gone wrong and needs human attention.
    if [ "$CURRENT_COUNT" -gt "$COUNT" ]; then
        echo "Unexpected number of fields in current version: $CURRENT_COUNT ; expected less-than-or-equal to $COUNT"
        return 1
    fi

    if [ "$CURRENT_COUNT" -lt "$COUNT" ]; then
        echo -n "${V}"
        while [ "$CURRENT_COUNT" -lt "$COUNT" ]; do
            echo -n ".0"
            CURRENT_COUNT=$(($CURRENT_COUNT + 1))
        done
    else
        # Extract the value of the last field
        MINOREST_FIELD="$(echo -n ${V} | rev | cut -d . -f 1 | rev)"
        NEW_MINOREST_FIELD=$(($MINOREST_FIELD + 1))
        # Cut off the minorest version of the version and append the newly calculated patch version
        echo -n "$(echo ${V} | rev | cut -d . -f 1 --complement | rev).$NEW_MINOREST_FIELD"
    fi
}

echo
echo "=========="
echo "Making sure we have kerberos"
echo "=========="
kinit -k -t /home/jenkins/ocp-build-buildvm.openshift.eng.bos.redhat.com.keytab ocp-build/buildvm.openshift.eng.bos.redhat.com@REDHAT.COM

# Path for merge-and-build script
MB_PATH=$(readlink -f $0)


if [ "$#" -ne 2 ]; then
  echo "Please pass in MAJOR and MINOR version"
  exit 1
else
  MAJOR="$1"
  MINOR="$2"
fi

OSE_VERSION="${MAJOR}.${MINOR}"
PUSH_EXTRA="--nolatest"

if [ -z "$WORKSPACE" ]; then
    echo "WORKSPACE environment variable has not been set. Aborting."
    exit 1
fi

# Use the directory relative to this Jenkins job.
BUILDPATH="${WORKSPACE}"

if [ -d "${BUILDPATH}/src" ]; then
    rm -rf "${BUILDPATH}/src" # Remove any previous clone
fi

RESULTS="${BUILDPATH}/results"
if [ -d "${RESULTS}" ]; then
    rm -rf "${RESULTS}"
fi
mkdir -p "${RESULTS}"

WORKPATH="${BUILDPATH}/src/github.com/openshift/"
mkdir -p ${WORKPATH}
cd ${BUILDPATH}
export GOPATH="$( pwd )"
echo "GOPATH: ${GOPATH}"
echo "BUILDPATH: ${BUILDPATH}"
echo "WORKPATH ${WORKPATH}"
echo "BUILD_MODE ${BUILD_MODE}"

go get github.com/jteeuwen/go-bindata

echo
echo "=========="
echo "Setup OIT stuff"
echo "=========="


pushd ${BUILDPATH}
OIT_DIR="${BUILDPATH}/enterprise-images/"
rm -rf ${OIT_DIR}
mkdir -p ${OIT_DIR}
OIT_PATH="${OIT_DIR}/tools/bin/oit"
git clone git@github.com:openshift/enterprise-images.git ${OIT_DIR}
popd

echo
echo "=========="
echo "Setup origin-web-console stuff"
echo "=========="
cd ${WORKPATH}
rm -rf origin-web-console
git clone git@github.com:openshift/origin-web-console.git
cd origin-web-console/
if [ "${BUILD_MODE}" == "online:stg" ] ; then
  WEB_CONSOLE_BRANCH="stage"
  git checkout "${WEB_CONSOLE_BRANCH}"
else
  WEB_CONSOLE_BRANCH="enterprise-${OSE_VERSION}"
  git checkout "${WEB_CONSOLE_BRANCH}"
fi

echo
echo "=========="
echo "Setup ose stuff"
echo "=========="
cd ${WORKPATH}
rm -rf ose
git clone git@github.com:openshift/ose.git
cd ose

OSE_DIR="${WORKPATH}/ose/"

# Enable fake merge driver used in our .gitattributes
# https://github.com/openshift/ose/commit/02b57ed38d94ba1d28b9bc8bd8abcb6590013b7c
git config merge.ours.driver true

# The number of fields which should be present in the openshift.spec Version field
SPEC_VERSION_COUNT=0

git checkout -q enterprise-${OSE_VERSION}
SPEC_VERSION_COUNT=3

VOUT="$(get_version_fields $SPEC_VERSION_COUNT)"
if [ "$?" != "0" ]; then
  echo "Error determining version fields: $VOUT"
  exit 1
fi

export TITO_USE_VERSION="--use-version $VOUT"

echo
echo "=========="
echo "Merge in origin-web-console stuff"
echo "=========="
VC_COMMIT="$(GIT_REF=${WEB_CONSOLE_BRANCH} hack/vendor-console.sh 2>/dev/null | grep "Vendoring origin-web-console" | awk '{print $4}')"
git add pkg/assets/bindata.go
git add pkg/assets/java/bindata.go
set +e # Temporarily turn off errexit. THis is failing sometimes. Check with Troy if it is expected.
git commit -m "Merge remote-tracking branch enterprise-${OSE_VERSION}, bump origin-web-console ${VC_COMMIT}"
set -e

# Put local rpm testing here

echo
echo "=========="
echo "Tito Tagging: ose"
echo "=========="
tito tag --accept-auto-changelog ${TITO_USE_VERSION}
export VERSION="$(grep Version: origin.spec | awk '{print $2}')"  # should match version arrived at by TITO_USE_VERSOIN
git push
git push --tags

echo
echo "=========="
echo "Tito Building: ose"
echo "=========="
TASK_NUMBER=`tito release --yes --test aos-${OSE_VERSION} | grep 'Created task:' | awk '{print $3}'`
echo "TASK NUMBER: ${TASK_NUMBER}"
echo "TASK URL: https://brewweb.engineering.redhat.com/brew/taskinfo?taskID=${TASK_NUMBER}"
echo
echo -n "https://brewweb.engineering.redhat.com/brew/taskinfo?taskID=${TASK_NUMBER}" > "${RESULTS}/ose-brew.url"
brew watch-task ${TASK_NUMBER}

echo
echo "=========="
echo "Setup: openshift-ansible"
echo "=========="
pushd ${WORKPATH}
rm -rf openshift-ansible
git clone git@github.com:openshift/openshift-ansible.git
OPENSHIFT_ANSIBLE_DIR="${WORKPATH}/openshift-ansible/"

cd openshift-ansible/
if [ "${MAJOR}" -eq 3 ] && [ "${MINOR}" -le 5 ] ; then # 3.5 and below maps to "release-1.5"
    git checkout -q release-1.${MINOR}
else  # Afterwards, version maps directly; 3.5 => "release-3.5"
    git checkout -q release-${OSE_VERSION}
fi

echo
echo "=========="
echo "Tito Tagging: openshift-ansible"
echo "=========="
if [ "${MAJOR}" -eq 3 -a "${MINOR}" -le 5 ] ; then # 3.5 and below
    # Use tito's normal progression for older releases
    export TITO_USE_VERSION=""
else
    # For 3.6 onward, match the OCP version
    export TITO_USE_VERSION="--use-version=${VERSION}"
fi

tito tag --accept-auto-changelog ${TITO_USE_VERSION}
git push
git push --tags

echo
echo "=========="
echo "Tito Building: openshift-ansible"
echo "=========="
TASK_NUMBER=`tito release --yes --test aos-${OSE_VERSION} | grep 'Created task:' | awk '{print $3}'`
echo "TASK NUMBER: ${TASK_NUMBER}"
echo "TASK URL: https://brewweb.engineering.redhat.com/brew/taskinfo?taskID=${TASK_NUMBER}"
echo
echo -n "https://brewweb.engineering.redhat.com/brew/taskinfo?taskID=${TASK_NUMBER}" > "${RESULTS}/openshift-ansible-brew.url"
brew watch-task ${TASK_NUMBER}
popd

echo
echo "=========="
echo "Signing RPMs"
echo "=========="
# "${WORKSPACE}/build-scripts/sign_rpms.sh" "rhaos-${OSE_VERSION}-rhel-7-candidate" "openshifthosted"

pushd "${WORKSPACE}"
COMMIT_SHA="$(git rev-parse HEAD)"
popd
PUDDLE_CONF_BASE="https://raw.githubusercontent.com/openshift/aos-cd-jobs/${COMMIT_SHA}/build-scripts/puddle-conf"
PUDDLE_CONF="${PUDDLE_CONF_BASE}/atomic_openshift-${OSE_VERSION}.conf"
PUDDLE_SIG_KEY="b906ba72"

echo
echo "=========="
echo "Building Puddle"
echo "=========="
ssh ocp-build@rcm-guest.app.eng.bos.redhat.com \
    sh -s -- --conf "${PUDDLE_CONF}" -b -d -n -s --label=building \
    < "${WORKSPACE}/build-scripts/rcm-guest/call_puddle.sh"

echo
echo "=========="
echo "Run OIT rebase"
echo "=========="

cat >"${OIT_WORKING}/sources.yml" <<EOF
ose: ${OSE_DIR}
openshift-ansible: ${OPENSHIFT_ANSIBLE_DIR}
EOF

${OIT_PATH} --user=ocp-build --metadata-dir ${OIT_DIR} --working-dir ${OIT_WORKING} --group openshift-${OSE_VERSION} \
--sources ${OIT_WORKING}/sources.yml \
images:rebase --version v${VERSION} \
--release 1 \
--message "Updating Dockerfile version and release v${VERSION}-1" --push

echo
echo "=========="
echo "Build OIT images"
echo "=========="

${OIT_PATH} --user=ocp-build --metadata-dir ${OIT_DIR} --working-dir ${OIT_WORKING} --group openshift-${OSE_VERSION} \
images:build \
--push-to-defaults --repo-type unsigned

ssh ocp-build@rcm-guest.app.eng.bos.redhat.com \
    sh -s -- --conf "${PUDDLE_CONF}" -b -d -n \
    < "${WORKSPACE}/build-scripts/rcm-guest/call_puddle.sh"

# Record the name of the puddle which was created
PUDDLE_NAME=$(ssh ocp-build@rcm-guest.app.eng.bos.redhat.com readlink "/mnt/rcm-guest/puddles/RHAOS/AtomicOpenShift/${OSE_VERSION}/latest")
echo "Created puddle on rcm-guest: /mnt/rcm-guest/puddles/RHAOS/AtomicOpenShift/${OSE_VERSION}/${PUDDLE_NAME}"

echo
echo "=========="
echo "Sync latest puddle to mirrors"
echo "=========="
ssh ocp-build@rcm-guest.app.eng.bos.redhat.com \
  sh -s "simple" "${VERSION}" "release"  \
  < "${WORKSPACE}/build-scripts/rcm-guest/push-to-mirrors.sh"

# push-to-mirrors.sh creates a symlink on rcm-guest with this new name and makes the
# directory on the mirrors match this name.
echo -n "v${VERSION}_${PUDDLE_NAME}" > "${RESULTS}/ose-puddle.name"

echo
echo "=========="
echo "Publish the oc binary"
echo "=========="
ssh ocp-build@rcm-guest.app.eng.bos.redhat.com \
    sh -s "$OSE_VERSION" "${VERSION}" \
    < "$WORKSPACE/build-scripts/rcm-guest/publish-oc-binary.sh"

for x in "${VERSION}/"{linux/oc.tar.gz,macosx/oc.tar.gz,windows/oc.zip}; do
    curl --silent --show-error --head \
        "https://mirror.openshift.com/pub/openshift-v3/clients/$x" \
        | awk '$2!="200"{print > "/dev/stderr"; exit 1}{exit}'
done


echo
echo "=========="
echo "Gather changelogs"
echo "=========="
ssh ocp-build@rcm-guest.app.eng.bos.redhat.com \
    sh -s "$OSE_VERSION" \
    < "$WORKSPACE/scripts/rcm-guest-print-latest-changelog-report.sh" > "${RESULTS}/changelogs.txt"

echo
echo
echo "=========="
echo "Finished"
echo "OCP ${VERSION}"
echo "=========="
