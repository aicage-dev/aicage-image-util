# Close Pull Request

Close an open GitHub pull request identified by:

- repository
- PR branch
- base branch

If no matching open pull request is found, the action exits successfully without logging noise.

## What It Does

The action:

1. Lists open pull requests for the given `repository`, `pr_branch`, and `base_branch`
2. If a PR is found:
   1. Closes it
   2. Deletes the PR branch
   3. Logs the closed PR number and title

## Inputs

| Name            | Required | Description                                  | Default             |
|-----------------|----------|----------------------------------------------|---------------------|
| `github_token`  | Yes      | GitHub token used by the GitHub CLI          |                     |
| `repository`    | Yes      | Repository in `owner/name` format            |                     |
| `pr_branch`     | Yes      | Branch name used by the pull request         |                     |
| `base_branch`   | Yes      | Base branch name of the pull request         |                     |
| `close_comment` | No       | Comment posted when closing the pull request | `Closing stale PR.` |

## Behavior

- If no open PR matches `pr_branch` and `base_branch`, the action exits successfully.

## Requirements

Typical workflow permissions:

```yaml
permissions:
  contents: write
  pull-requests: write
```

## Example

```yaml
name: Cleanup stale linter PR

on:
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      
      # Linter steps
      
      # Create PR if linter changed repo
        
      - name: Close stale PR
        if: <linter did not change repo condition>
        uses: <owner>/<repo>@v1
        with:
          github_token: ${{ github.token }}
          repository: ${{ github.repository }}
          pr_branch: autofix/${{ github.ref_name }}
          base_branch: ${{ github.ref_name }}
          close_comment: Closing stale linter PR.
```

## Local Action Example

```yaml
- name: Close stale PR
  uses: ./.github/actions/close-pull-request
  with:
    github_token: ${{ github.token }}
    repository: ${{ github.repository }}
    pr_branch: autofix/${{ github.ref_name }}
    base_branch: ${{ github.ref_name }}
```
