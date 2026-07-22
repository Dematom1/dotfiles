# 1Password secret template - SAFE TO COMMIT (references only, no real values).
#
# Populate ~/.secrets from your vault with:
#     refresh-secrets          # alias for the op inject command below
#     # op inject -f -i ~/Code/dotfiles/zsh/secrets.tpl -o ~/.secrets
#
# Requires a 1Password item named "dev-env" in the Private vault, with one
# field per variable below. On a new machine: `op signin` then `refresh-secrets`.

export B2_APPLICATION_KEY_ID="{{ op://Private/dev-env/B2_APPLICATION_KEY_ID }}"
export B2_APPLICATION_KEY="{{ op://Private/dev-env/B2_APPLICATION_KEY }}"
export GITHUB_ORG="{{ op://Private/dev-env/GITHUB_ORG }}"
