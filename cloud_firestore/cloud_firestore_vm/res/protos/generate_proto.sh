#!/bin/sh
protoc -- **/**.proto --dart_out=grpc:../../lib/src/proto