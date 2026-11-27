FROM busybox:1.37@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec AS build
FROM scratch
COPY --from=build /bin/sh /sh
COPY --from=0 /bin/ls /ls
COPY --from=busybox:1.37@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec /bin/cat /cat
USER 65532:65532
