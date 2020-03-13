#!/usr/bin/env sh
export NAME="cloud_firestore_vm"
export MODULE_PATH="./cloud_firestore/${NAME}"
export DESCRIPTION="Dart implementation of Cloud Firestore SDK that offers a cloud-hosted, noSQL database with live synchronization and offline support."

dart $PWD/dev/tools/lib/create_app.dart                                                      \
    --serviceAccount="$PWD/dev/tools/service-account.json"                                   \
    --name="${NAME}"                                                                         \
    --org='eu.long1'                                                                         \
    --description="${DESCRIPTION}"                                                           \
    --path="${MODULE_PATH}"                                                                  \
    --sha1='38eb99cf2426f2ea789fce2f4f19fd14ea580167'                                        \
    --sha256='0a12de1044e0623060576916742bd8cadb80a9c9be38303cf86c932c865fcb2e'              \
    --webClientId='233259864964-atj096gj4dkn2q5iciufgrugequubseo.apps.googleusercontent.com'