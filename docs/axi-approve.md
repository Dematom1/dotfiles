# Approve staged AXI releases

1. Run `just rebuild` to install `axi-approve` through Home Manager.
2. Check that `npm --version` reports 11.19.0 or newer. Authenticate npm as the maintainer of `argo-workflows-axi`, `argocd-axi`, and `datadog-axi`.
3. By default, `axi-approve` runs npm stage approval with `--auth-type=web`. npm prints a URL; open it in a browser and approve with the passkey. One-time setup: on npmjs.com, go to Account > Two-Factor Authentication / Security keys, add a security key, choose this Mac's passkey (Touch ID), and name it. Web authentication uses Touch ID for each approval. To use 1Password instead, install its CLI (`op`), enable desktop app integration and Touch ID authorization, and set the exact OTP field reference. Do not use a service account or unattended authentication:

   ```sh
   export AXI_APPROVE_OP_REF='op://VAULT/ITEM/one-time password'
   ```

   There is no vault search. If `AXI_APPROVE_OP_REF` is unset, web authentication is used by default. To explicitly use the hidden typed-code prompt instead, set `AXI_APPROVE_AUTH=otp`. Non-interactive use is refused.
4. Run `axi-approve` in a terminal. Inspect each version, then answer `y` to publish it. Any other answer skips it. Staged versions are approved oldest-first within each package, and the command verifies that `latest` points to the highest approved version. If it does not, the command prints the exact `npm dist-tag add <package>@<version> latest` repair command and exits unsuccessfully.

The command uses the public npm registry explicitly. It lists all staged versions for the three packages, shows their stage IDs and registry metadata, and downloads each tarball into a temporary directory to list its files. It does not extract or execute package contents. The temporary directory is removed before confirmation.

Source repository, commit, and workflow run come from SLSA provenance when `npm stage view --json` includes it. Missing fields display `not provided by npm stage view`; the command does not infer provenance from package names or claim to verify signatures. All stage metadata is also shown without truncation. Do not approve a release whose source you cannot establish.

Only a confirmed release triggers authentication. The browser URL and npm's web-auth output remain visible so you can complete approval. The typed-code mode reads hidden input, suppresses dependency output, and never writes the OTP to disk. npm requires the OTP as an argument, so it can be visible to privileged local process inspection during approval. Do not run this command through a command-recording wrapper.

No pending versions prints `nothing pending` and exits successfully without accessing 1Password. A failed inspection or approval prints a result for that version and causes exit code 1. The command continues with the remaining versions. It has no automatic-confirmation flag.

Run the offline check with `python3 tests/axi-approve.py`. The check stubs both npm and op and never contacts the registry or 1Password.
