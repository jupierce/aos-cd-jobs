#!/bin/bash -e

GIT_ROOT="/home/opsmedic/aos-cd/git"
TMPDIR="$HOME/aos-cd/tmp"
mkdir -p "${TMPDIR}"

# TMPTMP is a directory specific to each invocation. It will be
# deleted when the script terminates.
TMPTMP=$(mktemp -d -p "${TMPDIR}")

function on_exit() {
    rm -rf "${TMPTMP}"

    # JOBS is primarily designed to kill the autokey_loader process if it was launched
    JOBS="$(jobs -p)"
    if [[ ! -z "$JOBS" ]]; then
        if kill $JOBS; then
            echo "Background tasks terminated"
        else
            echo "Unable to terminate background tasks"
        fi
    fi
}

trap on_exit EXIT

function print_usage() {
  echo
  echo "Usage: $(basename $0) <clusterid> <operation> [options]"
  echo "Examples:"
  echo
  echo "  Cluster Operations:"
  echo "    $(basename $0) testcluster install"
  echo "    $(basename $0) testcluster delete"
  echo "    $(basename $0) testcluster upgrade"
  echo "    $(basename $0) testcluster status"
  echo
  echo "  Log Gathering Operations:"
  echo "  Output will be a tarball of cluster logs. Do not pipe to stdout."
  echo "    $(basename $0) <clusterid> logs"
  echo
}

function get_latest_openshift_ansible()  {
  if [[ "${1}" == "int" || "${1}" == "stg" ]]; then
    AOS_TMPDIR="${TMPTMP}/openshift-ansible_extract"
    mkdir -p "${AOS_TMPDIR}"

    pushd "$GIT_ROOT/openshift-ansible-ops/playbooks/adhoc/get_openshift_ansible_rpms"
      /usr/bin/ansible-playbook extract_openshift_ansible_rpms.yml -e cli_type=online -e cli_release=$1 -e cli_download_dir=${AOS_TMPDIR}
    popd

    export OPENSHIFT_ANSIBLE_INSTALL_DIR="${AOS_TMPDIR}"
  else
    export OPENSHIFT_ANSIBLE_INSTALL_DIR="$GIT_ROOT/openshift-tools/openshift/installer/atomic-openshift-${oo_version}"
  fi
}

if [ "$#" -lt 2 ]
then
  print_usage
  exit 1
fi

# Let's cd into where the script is.
cd "$(dirname "$0")"

export CLUSTERNAME=$1
export OPERATION=$2
shift 2
ARGS="$@"

################################################
# CLUSTER LOG GATHERING
# PLEASE DO NOT ADD ANY NEW OPERATIONS BEFORE HERE
################################################
if [ "${OPERATION}" == "logs" ]; then
  # Gather the logs for the specified cluster
  ./gather-logs.sh ${CLUSTERNAME}
  exit 0
fi

# Stdout from 'status' invocation is sent out verbatim after an
# online-first install/upgrade. Similar to logs operation, don't
# output any stdout before this point.
if [ "${OPERATION}" == "status" ]; then
  # Run the upgrade, including post_byo steps and config loop
  pushd ~/aos-cd/git/openshift-ansible-ops/playbooks/release/bin > /dev/null
    /usr/local/bin/autokeys_loader ./aos-cd-cluster-status.sh ${CLUSTERNAME}
  popd > /dev/null
  exit 0
fi

opts=`getopt -o ha: --long help,openshift-ansible: -n 'cicd-control' -- "$@"`
eval set -- "$opts"
OPENSHIFT_ANSIBLE_VERSION="latest"
help=0

while true; do
  case "$1" in
    -h | --help )    help=1; shift ;;
    -a | --openshift-ansible ) OPENSHIFT_ANSIBLE_VERSION="$2"; shift; shift ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

if [[ "$help" == "1" ]]; then
    print_usage
    exit 0
fi

# update git repos
# This needs review.
# This isn't very portable. This requires that the git dirs are already
# in place to do updates
set +x
# Prevent output from this operation unless it actually fails; just to keep logs cleaner

####USING TEST REPOS TEMPORARILY.
if  [ "${CLUSTERNAME}" != "dev-preview-int" ]; then
    echo "Re-enable git cloning before doing more upgrades!"
    exit 1
fi
# Pull in the supported version of openshift ansible
pushd $GIT_ROOT/ansible
    git fetch origin
    git checkout v2.3.0.0-1
    source hacking/env-setup
popd
# UNCOMMENT THE NEXT LINE TO UNDO THIS TEST.
# CLONE_RESULT=$(/usr/bin/ansible-playbook ./clone_ops_git_repos.yml)
if [ "$?" != "0" ]; then
  echo "Error updating git repos"
  echo "$CLONE_RESULTS"
fi
set -x

# Allow for "test-key" to do some testing.
# For now, all we will do is echo out the $CLUSTERNAME and $OPERATION variables
# and then exit successfully.
if  [ "${CLUSTERNAME}" == "test-key" ]; then

  if  [ "${OPERATION}" == "status" ]; then
    echo "This output represents the current status of the test-key cluster"
    echo "This is the second line"
    echo "This is the third and final"
    exit 0
  fi

  get_latest_openshift_ansible "int"
  echo "OPENSHIFT_ANSIBLE_INSTALL_DIR = [${OPENSHIFT_ANSIBLE_INSTALL_DIR}]"
  echo "Operation requested on mock cluster '${CLUSTERNAME}'. The operation is: '${OPERATION}' with options: ${ARGS}"
  echo "  OPENSHIFT_ANSIBLE_VERSION=${OPENSHIFT_ANSIBLE_VERSION}"

  exit 0
fi

source "$GIT_ROOT/openshift-ansible-private/private_roles/aos-cicd/files/${CLUSTERNAME}/${CLUSTERNAME}_vars.sh"

set -o xtrace

CLUSTER_SETUP_TEMPLATE_FILE="$GIT_ROOT/openshift-ansible-private/private_roles/aos-cicd/files/${CLUSTERNAME}/${CLUSTERNAME}_aws_cluster_setup.yml"
if [ ! -f ${CLUSTER_SETUP_TEMPLATE_FILE} ]; then
  echo "Unable to find ${CLUSTERNAME}'s cluster setup template file. Exiting..."
  exit 10
fi

# Update cluster setup changes to the releases directory
echo "Update cluster setup changes..."
/usr/bin/cp ${CLUSTER_SETUP_TEMPLATE_FILE} "$GIT_ROOT/openshift-ansible-ops/playbooks/release/bin"

# Get the version and env from the template file
oo_version="$(grep -Po '(?<=^g_install_version: ).*' "${CLUSTER_SETUP_TEMPLATE_FILE}" | /usr/bin/cut -c 1-3)"
oo_environment="$(grep -Po '(?<=^g_environment: ).*' "${CLUSTER_SETUP_TEMPLATE_FILE}")"

################################################
# CREATE CLUSTER
################################################
if [ "${OPERATION}" == "install" ]; then

  get_latest_openshift_ansible ${oo_environment}

  # Deploy all the things
  pushd ~/aos-cd/git/openshift-ansible-ops/playbooks/release/bin
    /usr/local/bin/autokeys_loader ./refresh_aws_tmp_credentials.py --refresh &> /dev/null &
    export AWS_DEFAULT_PROFILE=$AWS_ACCOUNT_NAME
    export SKIP_GIT_VALIDATION=TRUE
    /usr/local/bin/autokeys_loader ./aws_cluster_setup.sh ${CLUSTERNAME}
  popd

  echo
  echo "Deployment is complete. OpenShift Console can be found at https://${MASTER_DNS_NAME}"
  echo

################################################
# DELETE CLUSTER
################################################
elif [ "${OPERATION}" == "delete" ]; then

  # another layer of protection for delete clusters
  if [[ "${CLUSTERNAME}" != "dev-preview-int" ]] && [[ "${CLUSTERNAME}" != "cicd" ]]; then
    echo "INVALID CLUSTER, NOT DELTETING CLUSTER: '${CLUSTERNAME}'. Exiting...."
    exit 10
  fi

  # This updates the OPs inventory
  echo "Updating the OPs inventory..."
  /usr/share/ansible/inventory/multi_inventory.py --refresh-cache --cluster=${CLUSTERNAME} >/dev/null
  echo

  pushd "$GIT_ROOT/openshift-ansible-ops/playbooks/release/decommission"
    /usr/local/bin/autokeys_loader /usr/bin/ansible-playbook aws_remove_cluster.yml -e cli_clusterid=${CLUSTERNAME} -e cluster_to_delete=${CLUSTERNAME} -e run_in_automated_mode=True
  popd

  # This updates the OPs inventory
  echo "Updating the OPs inventory..."
  /usr/share/ansible/inventory/multi_inventory.py --refresh-cache --cluster=${CLUSTERNAME} >/dev/null

################################################
# UPGRADE CLUSTER
################################################
elif [ "${OPERATION}" == "upgrade" ]; then
  echo Doing upgrade

  ./disable-docker-timer-hack.sh "${CLUSTERNAME}" > /dev/null &

  # Get the latest openshift-ansible rpms
  get_latest_openshift_ansible ${oo_environment}

  # Run the upgrade, including post_byo steps and config loop
  pushd ~/aos-cd/git/openshift-ansible-ops/playbooks/release/bin
    /usr/local/bin/autokeys_loader ./refresh_aws_tmp_credentials.py --refresh &> /dev/null &

    # Kill all background jobs on normal exit or signal

    export AWS_DEFAULT_PROFILE=$AWS_ACCOUNT_NAME
    export SKIP_GIT_VALIDATION=TRUE
    /usr/local/bin/autokeys_loader ./aws_online_cluster_upgrade.sh ./ops-to-productization-inventory.py ${CLUSTERNAME}
  popd

else
  echo Error. Unrecognized operation. Exiting...
fi
