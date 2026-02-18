#!/bin/bash
# Install npx-managed skills
npx skills add vercel-labs/agent-skills
npx skills add vercel-labs/skills

echo ""
echo "Manual steps:"
echo "  - Enable superpowers plugin: claude plugins enable superpowers@superpowers-marketplace"
echo "  - Enable frontend-design plugin: claude plugins enable frontend-design@claude-plugins-official"
