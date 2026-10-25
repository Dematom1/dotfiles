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

  # The App key lives in this Mac's login Keychain. The watcher stays off until
  # the captain adds the binary to the key's access list (README.md "Local
  # signoff").
  services.signoff.enable = true;
}
