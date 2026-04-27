{
  lib,
  mkT3Code,
}:
mkT3Code (lib.importJSON ./channel.json)
