# GitLab worker trial

This repository tests running mwcli's GitLab CI jobs on a temporary GitHub-hosted
VM. GitLab schedules the job, clones its source and receives its logs and artifacts.
GitHub supplies the worker VM. A job-event webhook starts a worker automatically
when a job requiring only the `github` tag becomes pending. Each worker processes
one job; a periodic queue check recovers missed events.

## One-time setup

1. Publish `.github/workflows/gitlab-workers.yml` to `main` in `addshore/testing`.
2. In the Wikimedia GitLab mwcli project, open **Settings > CI/CD > Runners > New
   project runner**. Give it the description `GitHub worker trial`, the single tag
   `github`, disable **Run untagged jobs**, and allow unprotected refs
   if testing an MR. Restrict it to this project. Set its maximum job timeout to
   1800 seconds. Create it through this UI, rather than legacy registration tokens.
3. Copy its runner authentication token (`glrt-...`) directly into
   **addshore/testing > Settings > Secrets and variables > Actions > New repository
   secret**, named `GITLAB_RUNNER_TOKEN`. Do not commit or paste it into a workflow.

4. Add `GITLAB_API_READ_TOKEN` as an Actions secret. Use a project access token
   scoped to mwcli, with Reporter access and only `read_api`. The queue checker
   runs on a separate VM from the privileged worker. It checks current job status
   and requires exactly the `github` tag. The token must be renewed before expiry.
   The trial token created on 17 October 2026 expires on 16 November 2026.

Runner tags are configured in GitLab, not by the workflow. Only the queue-check
job has GitHub Contents read permission to fetch its trusted helper from `main`;
the worker has no GitHub token permissions and receives only the runner token.

## Queue a smoke test

Add this optional manual job on a test MR in the GitLab project. It is independent
of the existing mwcli workers and tests privileged Docker-in-Docker with TLS:

```yaml
github-runner-smoke:
  stage: test
  image: docker:26.1.1
  tags:
    - github
  services:
    - docker:26.1.1-dind
  variables:
    DOCKER_TLS_CERTDIR: /certs
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_VERIFY: "1"
    DOCKER_CERT_PATH: /certs/client
  needs: []
  cache: []
  timeout: 10m
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      when: manual
      allow_failure: true
  script:
    - docker version
    - docker info
    - docker run --rm alpine:3.22 echo "GitLab job running on a GitHub VM"
    - echo "GitHub runner trial passed" > github-runner-trial.txt
  artifacts:
    paths:
      - github-runner-trial.txt
    expire_in: 1 day
```

With the webhook enabled, click Play on the smoke job so it is pending; GitLab
will dispatch the GitHub workflow automatically. Before enabling the webhook, or
to troubleshoot it, open **addshore/testing > Actions > GitLab worker trial > Run
workflow**, choosing `main`. Leaving `job_id` empty checks the pending queue.

The workflow connects to GitLab, waits up to 120 seconds for work and exits after
one job. If no matching job arrives it exits without processing one. Open the
GitLab job to check its result and download `github-runner-trial.txt`; successful
completion of the GitHub workflow alone does not prove that a GitLab job passed.

The runner uses a Docker executor with privileged services and a shared
`/certs/client` volume. It pulls images directly, without the private WMCS mirror.
Disk availability is logged before and after the run. A later real integration
trial must confirm Docker storage is sufficient for the MediaWiki tests.

Normal cleanup unregisters only the temporary runner manager, keeping the
UI-created project runner for the next run. GitHub destroys the VM afterwards.
Forced cancellation can interrupt cleanup; inspect the GitLab runner if needed.
Revoke/delete the project runner and remove the Actions secret to retire the trial.

## GitLab webhook

A webhook named **GitHub worker trial** (ID 72) is prepared in
[the mwcli project](https://gitlab.wikimedia.org/repos/releng/cli/-/hooks).
Its job events are initially disabled until authentication is added and the workflow
is verified.

Create a fine-grained GitHub token with resource owner `addshore`, repository access
limited to `testing`, and **Repository permissions > Actions > Read and write**.
Metadata read access is automatic; no Contents write permission is needed. Set an
expiry and renew the header before it expires. Do not paste the token into chat or
commit it.

Edit the prepared GitLab webhook. Under **Custom headers**, add:

- Name: `Authorization`
- Value: `Bearer YOUR_GITHUB_TOKEN`

Keep the existing Accept header, SSL verification enabled, and other triggers
disabled. Once setup is complete, enable **Job events** and save.

The configured URL is:

```text
https://api.github.com/repos/addshore/testing/actions/workflows/gitlab-workers.yml/dispatches
```

Its custom payload is:

```json
{
  "ref": "main",
  "inputs": {
    "project_id": "{{project_id}}",
    "job_id": "{{build_id}}",
    "job_status": "{{build_status}}"
  }
}
```

Only pending events for project 16 run the queue check. That check re-reads the job
from GitLab, so completed jobs and incompatible tags do not start a worker. Other
job-status events produce a skipped workflow. A schedule checks the pending queue
approximately every ten minutes if a webhook is missed; GitHub can delay scheduled
runs. Separate GitLab jobs can start workers concurrently, subject to GitHub's hosted
runner concurrency limits. Events for the same GitLab job share a concurrency
group, so duplicates cannot start simultaneous workers. A duplicate that passes
the check before its job starts may still cause a later idle worker, which exits
after 120 seconds. The schedule recovers any remaining pending work.

All workers reuse the same GitLab runner registration and authentication token.
Each VM gets a random `.runner_system_id`, so managers are tracked and cleaned up
independently even if GitHub's VM image has a shared machine ID. No extra runner
registrations or tokens are needed.

To test the complete connection, retry the GitLab smoke job without manually
starting a GitHub workflow. Check the GitLab webhook's recent deliveries and the
GitHub Actions runs; GitLab should receive the test artifact as before.

Move to the `mwcli` tag only after a real integration job passes. Keep this trial
restricted to `github` for now. To disable automation, disable Job events in the
GitLab webhook and disable the GitHub workflow (otherwise its schedule can still
start workers). Delete the GitLab project access token and GitHub secrets when
retiring the experiment.

References:

- https://docs.gitlab.com/runner/commands/#gitlab-runner-run-single
- https://docs.gitlab.com/runner/commands/#gitlab-runner-unregister
- https://docs.gitlab.com/ci/docker/using_docker_build/#use-the-docker-executor-with-docker-in-docker
