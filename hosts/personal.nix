# Personal Mac only. Committed, so a fresh personal Mac rebuilds from git.
# Whatever you list here is ADDED to the shared base in ../configuration.nix
# (nix concatenates the homebrew lists). Add tools as you install them, commit,
# and they're reproduced forever - no need to know the list in advance.
{ ... }:

{
  homebrew = {
    brews = [
      # personal-only CLI tools
    ];
    casks = [
      # personal-only apps, e.g. "spotify"
    ];
  };
}
