#!/bin/bash  
set -ex

git submodule update --init --recursive
cp ./_config_theme.yml ./themes/minima/_config.yml

hexo clean
hexo generate
