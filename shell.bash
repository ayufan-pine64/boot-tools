#!/bin/bash

set -e

ID=$(docker build -q .)

exec docker run -it --rm -v "$(pwd):$(pwd)" -w "$(pwd)" "$ID" "$@"
