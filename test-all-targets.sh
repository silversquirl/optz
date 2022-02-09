#!/bin/sh -e
printf 'native: '
zig test optz.zig

test_with_runner() {
	printf '%s: ' "$2"
	zig test -target "$2" --test-cmd "$1" --test-cmd-bin optz.zig
}
test_with_qemu() {
	case "$1" in
		sparcv9) set -- sparc64 "$2";;
		powerpc) set -- ppc "$2";;
		powerpc64) set -- ppc64 "$2";;
	esac
	test_with_runner "qemu-$1-static" "$2"
}
test_targets() {
	grep -v '^#\|^$' | while IFS=- read -r arch os; do
		case "$os" in
			linux)
				test_with_qemu "$arch" "$arch-$os-gnu"
				test_with_qemu "$arch" "$arch-$os-musl"
				;;
			windows)
				test_with_runner wine "$arch-$os"
				;;
		esac
	done
}

test_targets <<EOF
# Tier 1
x86_64-linux
x86_64-windows

# Tier 2
aarch64-linux
arm-linux
i386-linux
mips-linux
powerpc-linux
riscv64-linux
sparcv9-linux
# std doesn't support (or is broken on) these archs
#mips64-linux
#powerpc64-linux

i386-windows
# Can't use wine for non-native archs
#aarch64-windows
#arm-windows
EOF
