# CLAUDE.md

## GitHub & Releases

When working with GitHub releases, always use tag-specific download URLs (e.g., `/releases/download/v1.0.0/file.dmg`) instead of `/releases/latest/download/` which doesn't resolve pre-releases.

## General Rules

Before starting any task that requires authentication (GitHub API, Docker Hub, OAuth tokens), verify credentials are valid first. If auth fails, stop and ask the user to re-authenticate rather than retrying.

Before making changes, confirm the correct target project/directory. Do not assume which codebase the user wants modified.

## Git Operations

When asked to commit and push, do ONLY that. Do not rebuild, regenerate, or update releases unless explicitly asked.

Never add yourself as a co-author or contributor in git commits. Use `git commit` without co-author trailers.

## Build & Release

For macOS/iOS projects: code signing and keychain operations frequently hang or fail. When a build hangs for more than 30 seconds, stop and report the issue rather than retrying silently. Suggest the user run signing steps manually.

## Deployment

After completing web UI changes (HTML/CSS/JS), always redeploy the Docker container if the project uses docker-compose. Run `docker-compose up -d --build` to apply changes.

When fixing bugs in deployed containerized apps, always check whether the container needs to be rebuilt and redeployed with the new code. Code changes alone are insufficient.
