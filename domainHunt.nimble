# Package

version       = "0.1.0"
author        = "nsaspy"
description   = "StarIntel Actor that hunts for domains"
license       = "MIT"
srcDir        = "src"
bin           = @["domainHunt"]


# Dependencies

requires "nim >= 1.6.14"
requires "https://github.com/lost-rob0t/starRouter.git"
