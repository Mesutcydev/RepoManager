# Built-in tool and permission catalog

Generated from the compiled Swift catalog. Arguments use the exact schemas in [tool-catalog.json](tool-catalog.json).

Read tools require selected-scope authorization. Local edits require Act. All remote writes require an immutable native review. Consequential/destructive writes also require owner authentication and specific confirmation; delete/transfer require the full repository name. Secret write tools are native-only and never exposed to model or agent execution.

Permissions below are coarse repository roles; GitHub also enforces endpoint-specific App/PAT permissions, organization approval and feature availability. Scope/identity/permissions/remote state are revalidated before a write. An accepted asynchronous operation is not a completion receipt.

## Actions

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `approve_deployment` | consequential | push | No | Granted scope only | `POST repos/{owner}/{repo}/actions/runs/{id}/pending_deployments` |
| `artifact_metadata` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/actions/artifacts/{id}` |
| `cancel_workflow` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/actions/runs/{id}/cancel` |
| `check_run_status` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/commits/{sha}/check-runs` |
| `delete_artifact` | consequential | push | No | Granted scope only | `DELETE repos/{owner}/{repo}/actions/artifacts/{id}` |
| `dispatch_workflow` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/actions/workflows/{id}/dispatches` |
| `download_artifact` | read | pull | No | Granted scope only | `GET asset-download` |
| `list_artifacts` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/actions/artifacts` |
| `list_workflows` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/actions/workflows` |
| `pending_deployments` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/actions/runs/{id}/pending_deployments` |
| `read_workflow_run` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/actions/runs/{id}` |
| `rerun_workflow` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/actions/runs/{id}/rerun` |
| `workflow_jobs` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/actions/runs/{id}/jobs` |
| `workflow_logs` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/actions/jobs/{id}/logs` |
| `workflow_status` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/actions/runs` |

## Activity

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `activity` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/events` |

## Administration

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `branch_protection` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/branches/{branch}/protection` |
| `collaborators` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/collaborators` |
| `create_repository` | consequential | admin | No | Unavailable | `POST user/repos` |
| `create_ruleset` | consequential | admin | No | Granted scope only | `POST repos/{owner}/{repo}/rulesets` |
| `create_webhook` | consequential | admin | No | Granted scope only | `POST repos/{owner}/{repo}/hooks` |
| `delete_branch_protection` | consequential | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}/branches/{branch}/protection` |
| `delete_environment` | consequential | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}/environments/{environment}` |
| `delete_repository` | destructive | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}` |
| `delete_ruleset` | consequential | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}/rulesets/{id}` |
| `delete_webhook` | consequential | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}/hooks/{id}` |
| `fork_repository` | mutation | push | No | Unavailable | `POST repos/{owner}/{repo}/forks` |
| `list_environments` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/environments` |
| `list_rulesets` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/rulesets` |
| `list_webhooks` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/hooks` |
| `remove_collaborator` | consequential | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}/collaborators/{username}` |
| `repository_settings` | consequential | admin | No | Granted scope only | `PATCH repos/{owner}/{repo}` |
| `set_branch_protection` | consequential | admin | No | Granted scope only | `PUT repos/{owner}/{repo}/branches/{branch}/protection` |
| `set_collaborator` | consequential | admin | No | Granted scope only | `PUT repos/{owner}/{repo}/collaborators/{username}` |
| `set_environment` | consequential | admin | No | Granted scope only | `PUT repos/{owner}/{repo}/environments/{environment}` |
| `transfer_repository` | destructive | admin | No | Granted scope only | `POST repos/{owner}/{repo}/transfer` |
| `update_ruleset` | consequential | admin | No | Granted scope only | `PUT repos/{owner}/{repo}/rulesets/{id}` |
| `update_webhook` | consequential | admin | No | Granted scope only | `PATCH repos/{owner}/{repo}/hooks/{id}` |

## Changes

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `create_branch` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/git/refs` |
| `create_tag` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/git/refs` |
| `delete_branch` | consequential | push | No | Granted scope only | `DELETE repos/{owner}/{repo}/git/refs/heads/{branch}` |
| `delete_tag` | consequential | push | No | Granted scope only | `DELETE repos/{owner}/{repo}/git/refs/tags/{tag}` |

## Collaboration

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `add_project_item` | mutation | push | No | Granted scope only | `GRAPHQL addProjectV2ItemById` |
| `comment_discussion` | mutation | push | No | Granted scope only | `GRAPHQL addDiscussionComment` |
| `create_discussion` | mutation | push | No | Granted scope only | `GRAPHQL createDiscussion` |
| `discussion_comments` | read | pull | No | Granted scope only | `GRAPHQL discussionComments` |
| `linked_projects` | read | pull | No | Granted scope only | `GRAPHQL projectsV2` |
| `list_discussions` | read | pull | No | Granted scope only | `GRAPHQL discussions` |
| `update_project_item` | mutation | push | No | Granted scope only | `GRAPHQL updateProjectV2ItemFieldValue` |

## General

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `calculator` | read | pull | No | Granted scope only | `GET local` |
| `datetime` | read | pull | No | Granted scope only | `GET local` |
| `file_read` | read | pull | No | Granted scope only | `GET local` |
| `find_tools` | read | pull | No | Granted scope only | `GET local` |
| `index_document` | read | pull | No | Granted scope only | `GET local` |
| `knowledge_base` | read | pull | No | Granted scope only | `GET local` |
| `unit_convert` | read | pull | No | Granted scope only | `GET local` |
| `web_fetch` | read | pull | No | Granted scope only | `GET local` |
| `web_search` | read | pull | No | Granted scope only | `GET local` |

## Issues

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `comment_issue` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/issues/{id}/comments` |
| `create_issue` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/issues` |
| `create_label` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/labels` |
| `create_milestone` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/milestones` |
| `delete_issue_comment` | consequential | push | No | Granted scope only | `DELETE repos/{owner}/{repo}/issues/comments/{id}` |
| `delete_label` | consequential | push | No | Granted scope only | `DELETE repos/{owner}/{repo}/labels/{label}` |
| `delete_milestone` | consequential | push | No | Granted scope only | `DELETE repos/{owner}/{repo}/milestones/{id}` |
| `edit_issue` | mutation | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/issues/{id}` |
| `edit_issue_comment` | mutation | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/issues/comments/{id}` |
| `edit_label` | mutation | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/labels/{label}` |
| `edit_milestone` | mutation | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/milestones/{id}` |
| `issue_comments` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/issues/{id}/comments` |
| `list_issues` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/issues` |
| `list_labels` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/labels` |
| `list_milestones` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/milestones` |
| `read_issue` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/issues/{id}` |
| `search_issues` | read | pull | No | Granted scope only | `GET search/issues` |

## Pull requests

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `draft_review` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/pulls/{id}/reviews` |
| `inline_comment` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/pulls/{id}/comments` |
| `list_pull_requests` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/pulls` |
| `merge_pull_request` | mutation | push | No | Granted scope only | `PUT repos/{owner}/{repo}/pulls/{id}/merge` |
| `open_pull_request` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/pulls` |
| `pull_request_files` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/pulls/{id}/files` |
| `pull_request_reviews` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/pulls/{id}/reviews` |
| `read_pull_request` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/pulls/{id}` |
| `ready_pull_request` | mutation | push | No | Granted scope only | `GRAPHQL markPullRequestReadyForReview` |
| `request_reviewers` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/pulls/{id}/requested_reviewers` |
| `resolve_thread` | mutation | push | No | Granted scope only | `GRAPHQL resolveReviewThread` |
| `review_threads` | read | pull | No | Granted scope only | `GRAPHQL reviewThreads` |
| `search_pull_requests` | read | pull | No | Granted scope only | `GET search/issues` |
| `submit_review` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/pulls/{id}/reviews/{review_id}/events` |
| `update_pull_request` | mutation | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/pulls/{id}` |

## Releases

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `create_release` | mutation | push | No | Granted scope only | `POST repos/{owner}/{repo}/releases` |
| `delete_release` | consequential | push | No | Granted scope only | `DELETE repos/{owner}/{repo}/releases/{id}` |
| `delete_release_asset` | consequential | push | No | Granted scope only | `DELETE repos/{owner}/{repo}/releases/assets/{id}` |
| `edit_release` | mutation | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/releases/{id}` |
| `list_releases` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/releases` |
| `read_release` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/releases/{id}` |
| `release_assets` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/releases/{id}/assets` |
| `upload_release_asset` | mutation | push | No | Granted scope only | `ASSET repos/{owner}/{repo}/releases/{id}/assets` |

## Repositories

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `compare_commits` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/compare/{base}...{head}` |
| `git_log` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/commits` |
| `list_branches` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/branches` |
| `list_tags` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/tags` |
| `repository_info` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}` |
| `search_code` | read | pull | No | Granted scope only | `GET search/code` |

## Secrets

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `delete_dependabot_secret` | consequential | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}/dependabot/secrets/{name}` |
| `delete_environment_secret` | consequential | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}/environments/{environment}/secrets/{name}` |
| `delete_secret` | consequential | admin | No | Granted scope only | `DELETE repos/{owner}/{repo}/actions/secrets/{name}` |
| `list_dependabot_secrets` | read | admin | No | Granted scope only | `GET repos/{owner}/{repo}/dependabot/secrets` |
| `list_environment_secrets` | read | admin | No | Granted scope only | `GET repos/{owner}/{repo}/environments/{environment}/secrets` |
| `list_secrets` | read | admin | No | Granted scope only | `GET repos/{owner}/{repo}/actions/secrets` |
| `set_dependabot_secret` | consequential | admin | Yes | Unavailable | `PUT repos/{owner}/{repo}/dependabot/secrets/{name}` |
| `set_environment_secret` | consequential | admin | Yes | Unavailable | `PUT repos/{owner}/{repo}/environments/{environment}/secrets/{name}` |
| `set_secret` | consequential | admin | Yes | Unavailable | `PUT repos/{owner}/{repo}/actions/secrets/{name}` |

## Security

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `code_scanning_alerts` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/code-scanning/alerts` |
| `dependabot_alerts` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/dependabot/alerts` |
| `secret_scanning_alerts` | read | pull | No | Granted scope only | `GET repos/{owner}/{repo}/secret-scanning/alerts` |
| `update_code_scanning_alert` | mutation | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/code-scanning/alerts/{id}` |
| `update_dependabot_alert` | mutation | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/dependabot/alerts/{id}` |
| `update_secret_scanning_alert` | consequential | push | No | Granted scope only | `PATCH repos/{owner}/{repo}/secret-scanning/alerts/{id}` |

## Workspace

| Tool | Risk | Role | Native only | External agents | Route / operation |
| --- | --- | --- | --- | --- | --- |
| `apply_patch` | localEdit | push | No | Granted scope only | `GET local` |
| `audit_secret_history` | read | pull | No | Granted scope only | `GET local` |
| `checkpoint` | localEdit | push | No | Granted scope only | `GET local` |
| `delete_file` | localEdit | push | No | Granted scope only | `GET local` |
| `git_diff` | read | pull | No | Granted scope only | `GET local` |
| `list_files` | read | pull | No | Granted scope only | `GET local` |
| `merge_branch` | localEdit | push | No | Granted scope only | `GET local` |
| `move_file` | localEdit | push | No | Granted scope only | `GET local` |
| `read_file` | read | pull | No | Granted scope only | `GET local` |
| `read_file_range` | read | pull | No | Granted scope only | `GET local` |
| `redact_secrets` | localEdit | push | No | Granted scope only | `GET local` |
| `replace_text` | localEdit | push | No | Granted scope only | `GET local` |
| `repository_context_map` | read | pull | No | Granted scope only | `GET local` |
| `request_user_approval` | read | pull | No | Granted scope only | `GET local` |
| `restore_checkpoint` | localEdit | push | No | Granted scope only | `GET local` |
| `revert_last_commit` | localEdit | push | No | Granted scope only | `GET local` |
| `scan_secrets` | read | pull | No | Granted scope only | `GET local` |
| `search_branch` | read | pull | No | Granted scope only | `GET local` |
| `select_hunks` | localEdit | push | No | Granted scope only | `GET local` |
| `upload_attachment` | localEdit | push | No | Granted scope only | `GET local` |
| `write_file` | localEdit | push | No | Granted scope only | `GET local` |

## Schema and execution limits

Unknown properties are rejected. Strings, arrays, numbers, enums and object nesting are bounded. Paths/refs/SHA/entity segments receive semantic validation in addition to schema validation. Secrets are entered in secure fields, sealed to GitHub public keys and excluded from tool context/output. Tool reviews expire after five minutes and cannot be approved by voice/API.

Draft: 30 changed files / 2 MiB snapshots. Text file: 256 KiB. Range: 200 lines. New repository attachment: 1 MiB. Tool steps: 25 with a repository, five otherwise. Artifacts/release assets: 50 MiB in encrypted bounded chunks. Searches/logs/maps disclose coverage/truncation.
