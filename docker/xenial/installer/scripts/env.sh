echo "configuring initial environment"
export ATLAS_BUILD_GITHUB_COMMIT_SHA=$(git rev-parse HEAD)
export ATLAS_BUILD_GITHUB_TAG=$(git describe --exact-match HEAD 2> /dev/null)
export ATLAS_BUILD_SLUG="arrjay/infra"
export BUILD_TIMESTAMP=$(date +%s)

export PASSWORD_STORE_DIR=$(pwd)/vault

echo "loading vault..."
for x in ${PASSWORD_STORE_DIR}/*.gpg ; do
  name=$(basename "${x}" .gpg)
  declare -x ${name}="$(pass ls ${name})"
done

