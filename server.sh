#!/usr/bin/env bash

export RACK_ENV=development

bundle exec bin/falcon serve -b http://localhost:4567 -n 1 --threaded
