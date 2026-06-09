{ pkgs, crossPkgs, archSpec, tools }:

let
  lib = pkgs.lib;
  penguinArch = archSpec.penguinName;
  compatNames = archSpec.compatNames or [ ];
  # Cross cc wrapper, used to resolve this arch's crt startup objects so the
  # drop-in sysroot is a self-consistent musl toolchain (crt + libc + loader).
  crossCC = "${crossPkgs.stdenv.cc}/bin/${crossPkgs.stdenv.cc.targetPrefix}cc";
  manifest = pkgs.writeText "manifest-${penguinArch}.txt" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList
        (toolName: tool: "${toolName}|${tool.mode or "copy"}|${tool.kind}|${tool.path}|${tool.linkTarget or ""}")
        tools
    )
  );
in
pkgs.runCommand "penguin-tools-${penguinArch}"
  {
    nativeBuildInputs = (with pkgs.buildPackages; [
      bash
      coreutils
      file
      findutils
      gnugrep
      gnused
      patchelf
    ]) ++ [ crossPkgs.stdenv.cc ];
  }
  ''
    set -euo pipefail

    readonly arch="${penguinArch}"
    readonly dylib_dir="$out/igloo_static/dylibs/$arch"
    readonly arch_dir="$out/igloo_static/$arch"

    mkdir -p "$dylib_dir" "$arch_dir"

    declare -A copied_dependencies=()

    is_elf() {
      file -b "$1" | grep -q '^ELF '
    }

    resolve_dependency() {
      local source_ref="$1"
      local soname="$2"
      local source_dir
      local rpath
      local lib_dir

      source_dir="$(dirname "$source_ref")"
      if [ -e "$source_dir/$soname" ]; then
        echo "$source_dir/$soname"
        return 0
      fi

      rpath="$(patchelf --print-rpath "$source_ref" 2>/dev/null || true)"
      IFS=: read -r -a lib_dirs <<< "$rpath"
      for lib_dir in "''${lib_dirs[@]}"; do
        lib_dir="''${lib_dir//\$ORIGIN/$source_dir}"
        if [ -e "$lib_dir/$soname" ]; then
          echo "$lib_dir/$soname"
          return 0
        fi
      done

      return 1
    }

    pad_interpreter() {
      local new_interp="$1"
      local old_interp="$2"
      local padded="$new_interp"

      while [ "''${#padded}" -lt "''${#old_interp}" ]; do
        padded="/$padded"
      done

      printf '%s' "$padded"
    }

    normalize_elf() {
      local dest="$1"
      local source_ref="$2"
      local interp
      local needed
      local resolved
      local new_interp
      local padded_interp

      interp="$(patchelf --print-interpreter "$source_ref" 2>/dev/null || true)"
      if [ -n "$interp" ]; then
        copy_dependency "$interp"
        new_interp="/igloo_static/dylibs/$arch/$(basename "$interp")"
        padded_interp="$(pad_interpreter "$new_interp" "$interp")"
      else
        padded_interp=""
      fi

      while IFS= read -r needed; do
        [ -n "$needed" ] || continue
        resolved="$(resolve_dependency "$source_ref" "$needed" || true)"
        [ -n "$resolved" ] || continue
        copy_dependency "$resolved"
      done < <(patchelf --print-needed "$source_ref" 2>/dev/null || true)

      patchelf --set-rpath "/igloo_static/dylibs/$arch" "$dest" 2>/dev/null || true

      if [ -n "$interp" ]; then
        # MIPS targets are flaky when patchelf rewrites the interpreter path.
        sed -i "s,$interp,$padded_interp,g" "$dest"
      fi
    }

    copy_dependency() {
      local source_path
      local source_real
      local ref_name
      local real_name
      local dest

      source_path="$1"
      source_real="$(readlink -f "$source_path")"
      # The name the consumer references (a soname like libstdc++.so.6, or the
      # interpreter ld-musl-<arch>.so.1) is usually a symlink to a differently
      # named real file (libstdc++.so.6.0.34, libc.so). We copy the real file
      # but must also expose it under the referenced name, or the musl loader --
      # which looks up the literal NEEDED/interp string -- can't find it.
      ref_name="$(basename "$source_path")"
      real_name="$(basename "$source_real")"

      dest="$dylib_dir/$real_name"

      if [ -z "''${copied_dependencies[$source_real]:-}" ]; then
        copied_dependencies[$source_real]=1

        cp -L "$source_real" "$dest"
        chmod u+w "$dest"

        if is_elf "$dest"; then
          normalize_elf "$dest" "$source_real"
        fi

        chmod 0555 "$dest" || true
      fi

      # Always (re)create the reference-name alias, even when the real file was
      # already copied for another consumer -- the same file may be reached
      # under several names (e.g. ld-musl-<arch>.so.1 and libc.so).
      if [ "$ref_name" != "$real_name" ]; then
        ln -sfn "$real_name" "$dylib_dir/$ref_name"
      fi
    }

    stage_binary() {
      local source_path="$1"
      local dest_path="$2"

      mkdir -p "$(dirname "$dest_path")"
      cp -L "$source_path" "$dest_path"
      chmod u+w "$dest_path"

      if is_elf "$dest_path"; then
        normalize_elf "$dest_path" "$source_path"
      fi

      chmod 0555 "$dest_path"
    }

    stage_tree() {
      local source_tree="$1"
      local dest_tree="$2"
      local rel
      local dest_path
      local source_path

      mkdir -p "$dest_tree"
      cp -aL "$source_tree"/. "$dest_tree"/
      chmod -R u+w "$dest_tree"

      while IFS= read -r rel; do
        dest_path="$dest_tree/$rel"
        source_path="$source_tree/$rel"
        if is_elf "$dest_path"; then
          normalize_elf "$dest_path" "$source_path"
        fi
      done < <(cd "$dest_tree" && find . -type f | sed 's#^\./##')
    }

    rewrite_text_refs() {
      local from="$1"
      local to="$2"
      local root="$3"

      if grep -Irl -- "$from" "$root" >/dev/null 2>&1; then
        grep -IrlZ -- "$from" "$root" | xargs -0r sed -i "s|$from|$to|g"
      fi
    }

    validate_tree() {
      local bad=0
      local link
      local target

      while IFS= read -r link; do
        target="$(readlink "$link")"
        case "$target" in
          /nix/store/*)
            echo "Forbidden symlink target in $link -> $target" >&2
            bad=1
            ;;
        esac
      done < <(find "$out/igloo_static" -type l)

      if grep -R -a -n -P '(?<![[:alnum:]_])/nix/store' "$out/igloo_static" >/tmp/penguin-store-check.txt 2>/dev/null; then
        cat /tmp/penguin-store-check.txt >&2
        bad=1
      fi

      # Every staged ELF must be runnable on the guest from this tree alone: its
      # interpreter and every NEEDED soname must resolve inside dylibs/<arch>.
      # The musl loader looks up those literal names, so a missing alias means
      # the binary silently fails to launch at runtime (not caught above).
      local elf interp needed
      while IFS= read -r elf; do
        is_elf "$elf" || continue
        interp="$(patchelf --print-interpreter "$elf" 2>/dev/null || true)"
        if [ -n "$interp" ] && [ ! -e "$dylib_dir/$(basename "$interp")" ]; then
          echo "Missing interpreter $(basename "$interp") for $elf" >&2
          bad=1
        fi
        while IFS= read -r needed; do
          [ -n "$needed" ] || continue
          if [ ! -e "$dylib_dir/$needed" ]; then
            echo "Missing NEEDED $needed for $elf" >&2
            bad=1
          fi
        done < <(patchelf --print-needed "$elf" 2>/dev/null || true)
      done < <(find "$arch_dir" "$dylib_dir" -type f)

      if [ "$bad" -ne 0 ]; then
        exit 1
      fi
    }

    # The "|| [ -n ... ]" keeps the last record even though the manifest has no
    # trailing newline (writeText joins lines with concatStringsSep); without it
    # `read` would consume the final tool into the variables but exit the loop
    # before staging it, silently dropping whichever tool sorts last.
    while IFS='|' read -r tool_name tool_mode tool_kind tool_path tool_link_target || [ -n "$tool_name" ]; do
      [ -n "$tool_name" ] || continue
      case "$tool_mode:$tool_kind" in
        copy:binary)
          stage_binary "$tool_path" "$arch_dir/$tool_name"
          ;;
        copy:tree)
          stage_tree "$tool_path" "$arch_dir/$tool_name"
          rewrite_text_refs "$tool_path" "/igloo_static/$arch/$tool_name" "$arch_dir/$tool_name"
          ;;
        symlink:binary|symlink:tree)
          ln -sfn "$tool_link_target" "$arch_dir/$tool_name"
          ;;
        *)
          echo "Unknown tool mode/kind: $tool_mode/$tool_kind" >&2
          exit 1
          ;;
      esac
    done < "${manifest}"

    ${lib.concatMapStringsSep "\n" (compatArch: ''
      ln -sfn "$arch" "$out/igloo_static/${compatArch}"
      ln -sfn "$arch" "$out/igloo_static/dylibs/${compatArch}"
    '') compatNames}

    # Stage a self-consistent drop-in sysroot for this arch: the crt startup
    # objects from this arch's own musl+gcc toolchain, plus libc.so/libgcc_s.so.1
    # symlinked into the matching dylibs dir. penguin compiles per-project
    # init.d/*.c drop-ins against this; sourcing the crt and the libc from the
    # same toolchain avoids the startup mismatch a foreign libc would cause.
    sysroot_lib="$out/igloo_static/sysroots/$arch/lib"
    mkdir -p "$sysroot_lib"
    for obj in Scrt1.o crti.o crtn.o crtbeginS.o crtendS.o; do
      src="$("${crossCC}" -print-file-name="$obj")"
      if [ ! -f "$src" ]; then
        echo "could not resolve crt object $obj for $arch (got: $src)" >&2
        exit 1
      fi
      cp "$src" "$sysroot_lib/$obj"
      chmod u+w "$sysroot_lib/$obj"
    done
    ln -sfn "../../../dylibs/$arch/libc.so" "$sysroot_lib/libc.so"
    ln -sfn "../../../dylibs/$arch/libgcc_s.so.1" "$sysroot_lib/libgcc_s.so.1"

    # Some tools bake their build-time /nix/store prefix into the binary's
    # rodata (e.g. CPython's PREFIX in libpython, ltrace's SYSCONFDIR) or into
    # leftover text config. These are compile-time fallbacks, overridden at
    # runtime, and point at paths that do not exist on the guest anyway. Rewrite
    # the store prefix everywhere so the tree carries no /nix/store references.
    # "/igloo_nix" is exactly as long as "/nix/store", so the substitution is
    # length-preserving and leaves ELF section offsets intact.
    find "$out/igloo_static" -type f -print0 \
      | xargs -0r sed -i 's|/nix/store|/igloo_nix|g'

    validate_tree
  ''
