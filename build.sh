#!/usr/bin/env bash
# Filename: build.sh
docker build --progress plain -t buildqemu .
docker run --rm -d --name build-qemu-wasm -v $(pwd):/qemu/:rw buildqemu

EXTRA_CFLAGS="-O3 -g -Wno-error=unused-command-line-argument -matomics -mbulk-memory -DNDEBUG -DG_DISABLE_ASSERT -D_GNU_SOURCE -sASYNCIFY=1 -pthread -sPROXY_TO_PTHREAD=1 -sFORCE_FILESYSTEM -sALLOW_TABLE_GROWTH -sTOTAL_MEMORY=2300MB -sWASM_BIGINT -sMALLOC=mimalloc --js-library=/build/node_modules/xterm-pty/emscripten-pty.js -sEXPORT_ES6=1 -sEXPORT_NAME="'QEMU'" -sASYNCIFY_IMPORTS=ffi_call_js" ; \
  docker exec -it build-qemu-wasm emconfigure /qemu/configure --static --target-list=x86_64-softmmu --cpu=wasm32 --cross-prefix= \
    --without-default-features --enable-system --with-coroutine=fiber --enable-virtfs \
    --extra-cflags="$EXTRA_CFLAGS" --extra-cxxflags="$EXTRA_CFLAGS" --extra-ldflags="-sEXPORTED_RUNTIME_METHODS=getTempRet0,setTempRet0,addFunction,removeFunction,TTY,FS" && \
  docker exec -it build-qemu-wasm emmake make -j $(nproc) qemu-system-x86_64

if [ $? != 0 ]; then
  echo "There was an error building the container";
  exit 1;
fi

rm -fr /tmp/test-js/
mkdir -p /tmp/test-js/htdocs/

# Build default image

rm -fr /tmp/pack/
mkdir /tmp/pack/
# docker build --output=type=local,dest=/tmp/pack/ ./examples/x86_64/image
docker build --progress=plain --output type=local,dest=/tmp/pack/ ./examples/x86_64-alpine/image/


cp ./pc-bios/{bios-256k.bin,vgabios-stdvga.bin,kvmvapic.bin,linuxboot_dma.bin} /tmp/pack/
docker cp /tmp/pack build-qemu-wasm:/
docker exec -it build-qemu-wasm /bin/sh -c "/emsdk/upstream/emscripten/tools/file_packager.py qemu-system-x86_64.data --preload /pack > load.js"

cp -R ./examples/x86_64/src/* /tmp/test-js/
for f in qemu-system-x86_64 qemu-system-x86_64.wasm qemu-system-x86_64.worker.js qemu-system-x86_64.data load.js ; do
  docker cp build-qemu-wasm:/build/${f} /tmp/test-js/htdocs/
done
