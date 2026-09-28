#!/usr/bin/env bash
# Build ffmpeg.exe for Windows, on Windows, and prove it is standalone.
#
# Run from a MINGW64 shell:  ./build-windows.sh
#
# Why this file owns the flags instead of the caller. An earlier version passed
# EXTRA_LDFLAGS from the CI matrix, and the matrix gave Windows
# '-Wl,--gc-sections' while Linux got '-static'. The reasoning behind that was
# "mingw links kernel32 dynamically, so -static only applies to glibc". That is
# the wrong half of the truth: -static governs MinGW's own libraries, not the
# Windows system ones, and the system ones are resolved by name by the loader
# either way. So the flag was withheld, the binary imported libwinpthread-1.dll
# and libiconv-2.dll, and it died in the loader before main on any machine that
# did not already have MSYS2 installed. The CI Verify step ran on the build host,
# where both DLLs are on PATH, so it passed. Flags in one file, check in another,
# check on the wrong machine.
set -euo pipefail
cd "$(dirname "$0")"

# Pinned here, not in the caller. build.sh reads this from the environment.
EXTRA_LDFLAGS="-static -Wl,--gc-sections"
export EXTRA_LDFLAGS

# 1. Preflight. A local build that fails in configure because a package is
#    missing looks nothing like the same failure in CI, and the difference is
#    what wastes the afternoon.
missing=()
for tool in gcc make nasm objdump; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "==> FATAL: missing ${missing[*]}" >&2
  echo "==> Install: pacman -S --needed base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-nasm" >&2
  exit 1
fi

# 2. Never relink stale objects. ffmpeg caches the configure result in
#    ffbuild/config.mak, and a link line that changes without a clean leaves
#    objects from the previous flag set. That produces a binary that is neither
#    the old build nor the new one, which is the worst of both.
if [ -f ffbuild/config.mak ]; then
  if grep -qF -- "$EXTRA_LDFLAGS" ffbuild/config.mak; then
    echo "==> Flags unchanged, keeping objects for a fast rebuild"
  else
    echo "==> Flags changed, running make distclean so nothing stale is linked"
    make distclean >/dev/null 2>&1 || true
  fi
fi

# 3. Configure and make. build.sh holds the configure line; do not duplicate it
#    here, because a second copy of that list is a second thing to forget.
./build.sh

# 4. The check that would have caught this. It reads the PE import table and
#    never runs the binary, so it works on a file that cannot start at all.
#    Running the exe below proves much less: on this machine MSYS2 supplies both
#    offending DLLs, so a dynamic build passes right here and dies on a user's.
deps=$(objdump -p ./ffmpeg.exe | sed -n 's/.*DLL Name: //p' | tr -d '\r' | sort -u)

bad=""
for dll in $deps; do
  case "${dll,,}" in
    bcrypt|gdi32|imm32|kernel32|msvcrt|ole32|secur32|shell32|user32|version|\
    winmm|ws2_32|bcryptprimitives|ntdll|shlwapi|psapi) ;;
    *) bad="$bad $dll" ;;
  esac
done

if [ -n "$bad" ]; then
  echo "==> FATAL: ffmpeg.exe imports non-system libraries:$bad" >&2
  echo "==> It will not start anywhere without MSYS2 installed. See the note" >&2
  echo "==> at the top of this file about -static." >&2
  exit 1
fi

echo "==> Imports are system-only:"
for dll in $deps; do echo "      $dll"; done

# 5. Runs, but proves only that it is not corrupt.
./ffmpeg.exe -hide_banner -version | head -1

size=$(wc -c < ./ffmpeg.exe)
echo "==> Size: $size bytes at ./ffmpeg.exe"
echo "==> Copy that single file to a machine with no MSYS2 and run:"
echo "    ffmpeg.exe -hide_banner -version"
