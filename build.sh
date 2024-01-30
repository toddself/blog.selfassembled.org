#!/bin/bash

# download latest blog-builder
PLATFORM=$(uname | tr A-Z a-z)
ARCH=$(uname -m)
BIN_NAME="blog-builder-${PLATFORM}-${ARCH}"
INPUT_PATH="dist/"

if [ -f ${BIN_NAME} ]; then
  echo "Binary exists"
else
  echo "Binary doesn't exist, downloading latest version"
  DOWNLOAD_URL=$(curl -s https://api.github.com/repos/toddself/blog-builder/releases/latest | jq -r ".assets[] | select(.name == \"${BIN_NAME}\").browser_download_url")
  curl -sLO $DOWNLOAD_URL
  chmod +x ${BIN_NAME}
fi

./${BIN_NAME} data "${INPUT_PATH}" 

# copy assets
cp -R assets/* "${INPUT_PATH}"/. || true

chmod -c -R +rX "${INPUT_PATH}" | while read line; do
  echo "::warning title=Invalid file permissions automatically fixed::$line"
done
