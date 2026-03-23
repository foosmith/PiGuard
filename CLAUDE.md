# CLAUDE.md

## GitHub & Releases

When working with GitHub releases, always use tag-specific download URLs (e.g., `/releases/download/v1.0.0/file.dmg`) instead of `/releases/latest/download/` which doesn't resolve pre-releases.

## General Rules

Before starting any task that requires authentication (GitHub API, Docker Hub, OAuth tokens), verify credentials are valid first. If auth fails, stop and ask the user to re-authenticate rather than retrying.

## Deployment

After completing web UI changes (HTML/CSS/JS), always redeploy the Docker container if the project uses docker-compose. Run `docker-compose up -d --build` to apply changes.
