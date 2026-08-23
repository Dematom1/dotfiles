# AI tool update digest

Generated: `2026-08-23T02:36:40Z`

## Action required

### Claude Code Homebrew cask
- Version: `2.1.205` -> `2.1.231`
- Source: [release notes](<https://github.com/anthropics/claude-code/releases>)
- Risk: `R3` - The Homebrew cask may differ from the active native Claude launcher\.
- Rollback: Choose one Claude owner and preserve the other version before changing the cask\.
- Release notes: No release\-note excerpt was available from the allowlisted source\.

### Automic Vault app and av
- Version: `3.5.0` -> `3.16.0`
- Source: [release notes](<https://github.com/automic-vault/automic-vault/releases>)
- Risk: `R3` - Signed app and CLI are a credential boundary and currently mismatch\.
- Rollback: Restore the previous cask/app and signed CLI stub as a pair\.
- Release notes: No release\-note excerpt was available from the allowlisted source\.

### Herdr
- Version: `0.7.4` -> `0.8.2`
- Source: [release notes](<https://github.com/kunchenguid/herdr/releases>)
- Risk: `R3` - FirstMate worker placement and protocol behavior are version\-gated\.
- Rollback: Restore the previous Homebrew keg or direct binary and verify protocol compatibility\.
- Release notes: No release\-note excerpt was available from the allowlisted source\.

### chrome\-devtools\-axi
- Version: `0.1.26` -> `0.1.29`
- Source: [release notes](<https://github.com/kunchenguid/chrome-devtools-axi/releases>)
- Risk: `R3` - It controls a browser and its MCP launcher\.
- Rollback: Restore the exact npm version and re\-check the tracked MCP launcher\.
- Release notes: No release\-note excerpt was available from the allowlisted source\.

## Review

### Pi web access
- Version: `0.14.0` -> `0.24.2`
- Source: [release notes](<https://github.com/nicobailon/pi-web-access/releases>)
- Risk: `R2` - Pi extensions run with full system access\.
- Rollback: Restore the exact Pi package pin in the test profile\.
- Release notes: No release\-note excerpt was available from the allowlisted source\.

### RTK
- Version: `0.43.0` -> `0.45.0`
- Source: [release notes](<https://github.com/rtk-ai/rtk/releases>)
- Risk: `R1` - Output wrapper behavior affects agent sessions\.
- Rollback: Restore the prior Homebrew keg\.
- Release notes: No release\-note excerpt was available from the allowlisted source\.

## Informational

None.

## Unknown source

### Treehouse
- Version: `2.3.0` -> `unknown`
- Source: [source](<https://kunchenguid.github.io/treehouse/install.sh>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: Keep the previous binary or installer artifact\.

### Skills CLI and generated skills
- Version: `unknown` -> `unknown`
- Source: [source](<https://github.com/vercel-labs/skills>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: Archive generated skills before refresh and restore the archived copies\.

### Model catalogs
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: Preserve the captain's explicit runtime model and environment\.

### pg\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### docker\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### npm\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### pypi\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### homebrew\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### slack\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### aws\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### gws\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### notion\-axi
- Version: `unknown` -> `unknown`
- Source: [source](<https://axi.md>)
- Reason: No allowlisted machine\-readable release source is configured\.
- Rollback: No rollback needed because the tool is absent\.

### GitHub algal/pi\-openai\-server\-compaction
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub DietrichGebert/ponytail
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub openai/codex
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub anomalyco/opencode
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub kunchenguid/no\-mistakes
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub cli/cli
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub lmnr\-ai/headroom
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub nicobailon/pi\-web\-access
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub anthropics/claude\-code
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub automic\-vault/automic\-vault
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub kunchenguid/herdr
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub kunchenguid/chrome\-devtools\-axi
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.

### GitHub rtk\-ai/rtk
- Version: `unknown` -> `unknown`
- Source: source unavailable
- Reason: HTTP 403
- Rollback: Retry the read\-only source check later\.
