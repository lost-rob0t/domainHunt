# Package

version       = "0.1.0"
author        = "nsaspy"
description   = "StarIntel Actor that hunts for domains"
license       = "MIT"
srcDir        = "src"
bin           = @["domainHunt"]


# Dependencies

requires "nim >= 2.0.0"
requires "cligen"
requires "https://github.com/treeform/ws.git#c9c0c7b51e2e83cc9305a895a0b144a297b4bea8"
requires "https://github.com/lost-rob0t/starintel-doc.nim.git#827f2c072e9893561a1925c47f898458bafd6759"
requires "https://github.com/lost-rob0t/starRouter.git#20e5c9e8bf49660fd230d8e7306dd9209648f6e9"
