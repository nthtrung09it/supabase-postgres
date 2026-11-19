{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          # tzdata 2026f for PostgreSQL (--with-system-tzdata) until nixpkgs catches up.
          # Drop once the pinned nixpkgs ships >= 2026f (the assertion below trips).
          #
          # FORK (pg-18-*): upstream overrides the GLOBAL `tzdata`, which changes the hash
          # of everything that depends on it (python3, llvm, nodejs, gtk, rustc, ...): 1497
          # derivations then miss cache.nixos.org. Upstream gets them from its own S3 cache;
          # this fork builds without it (SUPABASE_NIX_CACHE= — 3-17 KB/s from sgp1), so the
          # 18.7 build died compiling the world. Here 2026f is a NEW attribute that only
          # nix/postgresql/default.nix uses, so nothing else is rebuilt, and upstream's vde2
          # override (only needed because of the global tzdata) is dropped.
          (
            final: prev:
            let
              # renovate: datasource=github-tags packageName=eggert/tz
              version = "2026f";
            in
            {
              postgresqlTzdata = prev.tzdata.overrideAttrs (
                old:
                assert final.lib.assertMsg (
                  # Versions are <year><letter>, so plain string ordering is chronological.
                  old.version < version
                ) "nixpkgs tzdata ${old.version} is not older than ${version}; remove the tzdata override";
                {
                  inherit version;
                  # 2026f no longer installs share/zoneinfo-posix or share/zoneinfo-leaps (no more leap seconds)
                  # patch old.postInstall so it doesn't fail when not found
                  postInstall =
                    builtins.replaceStrings
                      [
                        "rm $out/share/zoneinfo-posix\n"
                        "mv $out/share/zoneinfo-leaps $out/share/zoneinfo/right\n"
                      ]
                      [
                        ""
                        ""
                      ]
                      old.postInstall;
                  # now.ck fails for builds after 2026-11-01 because zonenow.tab lists zones that became identical.
                  # Run it at the release time, same as https://github.com/NixOS/nixpkgs/pull/582577.
                  # (upstream supabase/postgres 857951b5, branch fix/tzdata-check-timestamp, not yet released)
                  preCheck = ''
                    release_time_t=$(date -d "$(awk '/^Release /{print $4, $5, $6; exit}' NEWS)" +%s)
                    checkFlagsArray+=("CHECK_NOW_TIMESTAMP=$release_time_t")
                  '';
                  srcs = [
                    (final.fetchurl {
                      url = "https://data.iana.org/time-zones/releases/tzdata${version}.tar.gz";
                      hash = "sha256-AbSpHOxRZ+1IwR6Kt48gSM6teM6UsMr8rQroxaMETT0=";
                    })
                    (final.fetchurl {
                      url = "https://data.iana.org/time-zones/releases/tzcode${version}.tar.gz";
                      hash = "sha256-WhjaATk2ee8lWSFNxodWP389BWkfb1i3+8AWbz55bNY=";
                    })
                  ];
                }
              );
              # pre-commit's test suite pulls in dotnet-sdk, which depends on tzdata.
              # dotnet-sdk fails to build with
              # > The specified version string '7.1.2.71102' does not conform to the recommended format - major.minor.build.revision
              # 1102 looks like the current date (when CI tried to build and failed...), on 10/31 the revision was 71031.
              pre-commit = prev.pre-commit.overridePythonAttrs {
                doCheck = false;
                preCheck = "";
                # pytestCheckPhase runs as a preDist phase regardless of doCheck, and its
                # flags include --forked (pytest-forked), which isn't available here.
                dontUsePytestCheck = true;
              };
              pythonPackagesExtensions =
                prev.pythonPackagesExtensions
                ++ final.lib.optionals prev.stdenv.hostPlatform.isDarwin [
                  (_pyFinal: pyPrev: {
                    # test_timeout expects regex's timeout= to fire on a busy-wait callback; it doesn't on darwin.
                    backrefs = pyPrev.backrefs.overridePythonAttrs (old: {
                      disabledTests = (old.disabledTests or [ ]) ++ [ "test_timeout" ];
                    });
                    # setproctitle's fork tests segfault on darwin, skip them for now since linux is still good; skip them.
                    setproctitle = pyPrev.setproctitle.overridePythonAttrs { doCheck = false; };
                    uvloop = pyPrev.uvloop.overridePythonAttrs (old: {
                      disabledTests = (old.disabledTests or [ ]) ++ [ "test_cancel_post_init" ];
                    });
                  })
                ];
              # node's test suite fails on darwin
              nodejs = prev.nodejs.overrideAttrs { doCheck = !prev.stdenv.hostPlatform.isDarwin; };
            }
          )
          (
            let
              # Provide older versions of packages required by some extensions
              oldstable = import inputs.nixpkgs-oldstable { inherit system; };
              nixos2211 = import inputs.nixpkgs-2211 { inherit system; };
            in
            _final: _prev: {
              v8_oldstable = oldstable.v8;
              clang11 = nixos2211.clang;
            }
          )
        ];
      };
    };
}
