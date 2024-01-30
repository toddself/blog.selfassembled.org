# handle images
shopt -s nullglob dotglob
if [ -e $PWD/raw_images ]; then
  RAW_FILE_LIST=($PWD/raw_images/*jpg)
  if [ ${#RAW_FILE_LIST[@]} -gt 0 ]; then
    echo $RAW_FILE_LIST
    for IMG in $PWD/raw_images/*jpg; do
      BASE=$(basename $IMG)
      DEST="assets/${BASE}"
      echo "Converting ${IMG} to ${DEST}"
      convert "${IMG}" -resize 1600x1600 -quality 40 -strip "${DEST}"
    done
    rm $PWD/raw_images/*jpg
  fi
fi

