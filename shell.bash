#!/bin/bash

set -e

ID=$(docker build -q - < Dockerfile)

exec docker run -it --rm -v "$(pwd):$(pwd)" -w "$(pwd)" "$ID" "$@"
