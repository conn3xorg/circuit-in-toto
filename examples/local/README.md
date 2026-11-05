# Local example

Applies circuit-in-toto to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.`

Want to see it catch something? `check.sh` makes three keys on the host, an owner's layout with two steps and an inspection, and runs a small build through `in-toto-run`. It checks that `in-toto-verify` accepts the build, then that it refuses one where the source changed between the steps, and one where the tarball was swapped afterwards. No network or GPG involved:

```sh
podman exec -i circuit-in-toto sh -s 3.1.0 < check.sh
```

The argument is the version it expects `in-toto-run --version` to report. Leave it out to skip that part. The two refusals print in-toto's own errors, which is what passing looks like; the last line says so.

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINER_NAME` to name the container something else. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses. On a Mac, rootful Podman is simplest: `export CONTAINER_CONNECTION=podman-machine-default-root`.

`./down.sh` removes the container, its volumes, the key and the state.
