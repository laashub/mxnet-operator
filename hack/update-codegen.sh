#!/bin/bash

# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This shell is used to auto generate some useful tools for k8s, such as lister,
# informer, deepcopy, defaulter and so on.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_ROOT=$(dirname "${BASH_SOURCE[0]}")/..
ROOT_PKG=github.com/kubeflow/mxnet-operator

# Grab code-generator version from go.sum
CODEGEN_VERSION=$(grep 'k8s.io/code-generator' go.sum | awk '{print $2}' | head -1)
CODEGEN_PKG=$(echo `go env GOPATH`"/pkg/mod/k8s.io/code-generator@${CODEGEN_VERSION}")

if [[ ! -d ${CODEGEN_PKG} ]]; then
    echo "${CODEGEN_PKG} is missing. Running 'go mod download'."
    go mod download
fi

echo ">> Using ${CODEGEN_PKG}"

# code-generator does work with go.mod but makes assumptions about
# the project living in `$GOPATH/src`. To work around this and support
# any location; create a temporary directory, use this as an output
# base, and copy everything back once generated.
TEMP_DIR=$(mktemp -d)
cleanup() {
    echo ">> Removing ${TEMP_DIR}"
    rm -rf ${TEMP_DIR}
}
trap "cleanup" EXIT SIGINT

echo ">> Temporary output directory ${TEMP_DIR}"

# Ensure we can execute.
chmod +x ${CODEGEN_PKG}/generate-groups.sh

# generate the code with:
# --output-base    because this script should also be able to run inside the vendor dir of
#                  k8s.io/kubernetes. The output-base is needed for the generators to output into the vendor dir
#                  instead of the $GOPATH directly. For normal projects this can be dropped.
cd ${SCRIPT_ROOT}
${CODEGEN_PKG}/generate-groups.sh "defaulter,deepcopy,client,informer,lister" \
 github.com/kubeflow/mxnet-operator/pkg/client github.com/kubeflow/mxnet-operator/pkg/apis \
 mxnet:v1beta1,v1 \
 --output-base "${TEMP_DIR}" \
 --go-header-file hack/boilerplate/boilerplate.go.txt

# Notice: The code in code-generator does not generate defaulter by default.
# We need to build binary from vendor cmd folder.
echo "Building defaulter-gen"
go build -o defaulter-gen ${CODEGEN_PKG}/cmd/defaulter-gen

echo "Generating defaulters for v1beta1"
./defaulter-gen --input-dirs github.com/kubeflow/mxnet-operator/pkg/apis/mxnet/v1beta1 \
  -O zz_generated.defaults \
  --go-header-file hack/boilerplate/boilerplate.go.txt \
  --output-package github.com/kubeflow/mxnet-operator/pkg/apis/mxnet/v1beta1

echo "Generating defaulters for v1"
./defaulter-gen --input-dirs github.com/kubeflow/mxnet-operator/pkg/apis/mxnet/v1 \
  -O zz_generated.defaults \
  --go-header-file hack/boilerplate/boilerplate.go.txt \
  --output-package github.com/kubeflow/mxnet-operator/pkg/apis/mxnet/v1

# Copy everything back.
cp -a "${TEMP_DIR}/${ROOT_PKG}/." "${SCRIPT_ROOT}/"
# Clean up binaries we build for update codegen
rm ./defaulter-gen