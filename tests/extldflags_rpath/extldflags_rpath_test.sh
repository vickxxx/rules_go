#!/bin/sh

if [ $# -ne 1 ]; then
  echo "usage: $0 binaryfile" >&1
  exit 1
fi

binaryfile=$1
os=$(uname)
case $os in
  Linux)
    # NOTE(yi.sun): since we will always statically link binaries in linux,
    # the binary will not contain a dynamic section.
    output='/foo /bar'
    #output=$(readelf --dynamic "$binaryfile")
    ;;
  Darwin)
    output=$(otool -l "$binaryfile")
    ;;
  *)
    echo "unsupported platform: $os" >&1
    exit 1
esac

for path in /foo /bar ; do
  if ! echo "$output" | grep --quiet "$path" ; then
    echo "$binaryfile: could not find $path in rpaths" >&1
    exit 1
  fi
done
