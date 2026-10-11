{
  description = "DomainHunt consuming the generated StarLang wire contract";
  inputs = {
    star-router.url = "github:lost-rob0t/starRouter/20e5c9e8bf49660fd230d8e7306dd9209648f6e9";
    nixpkgs.follows = "star-router/nixpkgs";
    starintel-doc.follows = "star-router/starintel-doc";
    ws = { url = "github:treeform/ws/c9c0c7b51e2e83cc9305a895a0b144a297b4bea8"; flake = false; };
  };
  outputs = { self, nixpkgs, star-router, starintel-doc, ws }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      python = pkgs.python3.withPackages (p: [p.pyzmq p.websockets]);
      paths = "--noNimblePath --path:src --path:${starintel-doc}/src --path:${star-router}/src --path:${ws}/src --path:${star-router.inputs.cligen} --path:${star-router.inputs.zmq} --path:$TMPDIR/ulid-deps";
      libraries = pkgs.lib.makeLibraryPath [ pkgs.pcre pkgs.zeromq pkgs.openssl ];
      actor = pkgs.stdenv.mkDerivation {
        pname = "domainHunt";
        version = "0.1.0";
        src = self;
        nativeBuildInputs = [ pkgs.nim python pkgs.makeWrapper pkgs.openssl ];
        buildInputs = [ pkgs.openssl ];
        buildPhase = ''
          # Nim 2.2.12 otherwise gives pkg/random and std/random the same C name.
          # Rename only the pinned ULID RNG module; its implementation is unchanged.
          mkdir -p "$TMPDIR/ulid-deps"
          cp -r ${star-router.inputs.ulid}/src/. "$TMPDIR/ulid-deps/"
          cp -r ${star-router.inputs.random}/src/. "$TMPDIR/ulid-deps/"
          mv "$TMPDIR/ulid-deps/random.nim" "$TMPDIR/ulid-deps/ulid_random.nim"
          chmod u+w "$TMPDIR/ulid-deps/ulid.nim"
          substituteInPlace "$TMPDIR/ulid-deps/ulid.nim" --replace-fail 'import pkg/random' 'import ulid_random'
          nim c -d:release -d:ssl ${paths} --nimcache:"$TMPDIR/nimcache" --out:domainHunt src/domainHunt.nim
        '';
        doCheck = true;
        doInstallCheck = true;
        checkPhase = ''
          python scripts/sync-starintel-schema.py --offline
          python scripts/check-runtime-release.py ${starintel-doc} ${star-router}
          export LD_LIBRARY_PATH=${libraries}
          export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          python tests/domain_wire.py "$PWD/domainHunt" ${star-router.packages.${system}.default}/bin/starRouter
          python tests/domain_wire.py "$PWD/domainHunt" ${star-router.packages.${system}.default}/bin/starRouter --tls
          python tests/domain_wire.py "$PWD/domainHunt" ${star-router.packages.${system}.default}/bin/starRouter --tls-untrusted
        '';
        installPhase = ''
          mkdir -p "$out/bin"
          install -m755 domainHunt "$out/bin/domainHunt"
          wrapProgram "$out/bin/domainHunt" --prefix LD_LIBRARY_PATH : ${libraries} \
            --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        '';
        installCheckPhase = ''
          python tests/domain_wire.py "$out/bin/domainHunt" ${star-router.packages.${system}.default}/bin/starRouter
          python tests/domain_wire.py "$out/bin/domainHunt" ${star-router.packages.${system}.default}/bin/starRouter --tls
          python tests/domain_wire.py "$out/bin/domainHunt" ${star-router.packages.${system}.default}/bin/starRouter --tls-untrusted
        '';
      };
    in {
      packages.${system}.default = actor;
      apps.${system} = {
        default = self.apps.${system}.domainHunt;
        domainHunt = { type = "app"; program = "${actor}/bin/domainHunt"; };
      };
      checks.${system}.default = actor;
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.nim pkgs.nimble python ];
        LD_LIBRARY_PATH = libraries;
      };
    };
}
