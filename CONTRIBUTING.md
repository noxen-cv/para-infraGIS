# Contributing to para-InfraGIS

Thanks for contributing to the Para infrastructure stack.

## Contribution Scope

This repository focuses on infrastructure and map asset delivery for Para clients, including:

- Deployment scripts in `scripts/deploy/`
- Infrastructure code in `infra/terraform/`
- Runbooks in `docs/runbooks/`
- Client consumption docs in `docs/api/`
- Canonical thematic style in `src/styles/v1/para-gold.json`

## Start With Issues

Before coding, check open issues for bugs and feature requests.

- Bug reports and bug triage should use `.github/ISSUE_TEMPLATE/bug_report.md`.
- Feature proposals should use `.github/ISSUE_TEMPLATE/feature_request.md`.

If no matching issue exists, open one first so maintainers can confirm scope and priority.

## Open Source Workflow

1. Fork the repository and create your branch from `main`.
2. Link your branch and commits to an issue.
3. Keep changes scoped to one logical concern.
4. Run validations relevant to your change.
5. Open a pull request using `.github/PULL_REQUEST_TEMPLATE/pull_request_template.md`.

## Pull Request Requirements

When opening a PR, include:

- Problem statement and linked issue
- Summary of what changed
- Validation evidence (commands, logs, screenshots if needed)
- Rollback notes for deployment-impacting changes

Small, focused PRs are preferred over large multi-scope PRs.

## Repository Structure Reference

Use this high-level map to place your changes correctly:

- `src/styles/` style JSON sources
- `scripts/deploy/` deployment and bootstrap scripts
- `infra/terraform/` IaC definitions and environment configs
- `docs/runbooks/` operational procedures
- `docs/api/` client integration contracts
- `.github/` workflow and template governance

## Optional GitHub Automation Setup

This repo includes style deployment automation in `.github/workflows/deploy-style.yml`.

If you want to enable automatic style deployment in your fork, configure these repository secrets:

- `AZ_SUBSCRIPTION_ID`
- `AZURE_CREDENTIALS` (JSON) or split service principal values (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZ_SUBSCRIPTION_ID`)
- Optional key fallback: `AZURE_STORAGE_KEY`

The workflow is path-filtered and intended for style deployment updates. Keep automation-related changes explicit in your PR description.

## Notes for App Contributors

If you are testing map consumption from the mobile app, use a custom development build or production build, not Expo Go, to avoid false blank-map results.
