# Approve staged AXI releases

1. Run `just rebuild` to install `axi-approve` through Home Manager.
2. Check that `npm --version` reports 11.19.0 or newer. Authenticate npm as the maintainer of `argo-workflows-axi`, `argocd-axi`, and `datadog-axi`.
3. Install the 1Password CLI (`op`). Enable its desktop app integration and Touch ID authorization. Do not use a service account or unattended authentication for this command.
4. Set the exact OTP field reference. Replace the placeholder vault and item with your npm login item:

   ```sh
   export AXI_APPROVE_OP_REF='op://VAULT/ITEM/one-time password'
   ```

   There is no default reference and no vault search. The reference itself is not an OTP and can go in your shell configuration.
5. Run `axi-approve` in a terminal. Inspect each version, then answer `y` to publish it. Any other answer skips it.

The command uses the public npm registry explicitly. It lists all staged versions for the three packages, shows their stage IDs and registry metadata, and downloads each tarball into a temporary directory to list its files. It does not extract or execute package contents. The temporary directory is removed before confirmation.

Source repository, commit, and workflow run come from SLSA provenance when `npm stage view --json` includes it. Missing fields display `not provided by npm stage view`; the command does not infer provenance from package names or claim to verify signatures. All stage metadata is also shown without truncation. Do not approve a release whose source you cannot establish.

Only a confirmed release triggers `op read`. Each approval reads a fresh OTP immediately before `npm stage approve`. The command suppresses dependency output and disables npm debug logs. It never writes the OTP to disk. npm requires the OTP as an argument, so it can be visible to privileged local process inspection during approval. Do not run this command through a command-recording wrapper.

No pending versions prints `nothing pending` and exits successfully without accessing 1Password. A failed inspection or approval prints a result for that version and causes exit code 1. The command continues with the remaining versions. It has no automatic-confirmation flag.

Run the offline check with `python3 tests/axi-approve.py`. The check stubs both npm and op and never contacts the registry or 1Password.
