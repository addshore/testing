# GitLab worker trial

This repository tests running mwcli's GitLab CI jobs on a temporary GitHub-hosted
VM. GitLab schedules the job, clones its source and receives its logs and artifacts.
GitHub supplies the worker VM. The first trial is manual and processes one job.

## One-time setup

1. Publish `.github/workflows/gitlab-workers.yml` to `main` in `addshore/testing`.
2. In the Wikimedia GitLab mwcli project, open **Settings > CI/CD > Runners > New
   project runner**. Give it the description `GitHub worker trial`, the single tag
   `mwcli-github-test`, disable **Run untagged jobs**, and allow unprotected refs
   if testing an MR. Restrict it to this project. Set its maximum job timeout to
   1800 seconds. Create it through this UI, rather than legacy registration tokens.
3. Copy its runner authentication token (`glrt-...`) directly into
   **addshore/testing > Settings > Secrets and variables > Actions > New repository
   secret**, named `GITLAB_RUNNER_TOKEN`. Do not commit or paste it into a workflow.

No GitLab API management token, GitHub dispatch token or webhook is needed for
this first manual trial. Runner tags are configured in GitLab, not by the workflow.
The workflow requests no GitHub token permissions and does not check out source
from the testing repository.

## Queue a smoke test

Add this optional manual job on a test MR in the GitLab project. It is independent
of the existing mwcli workers and tests privileged Docker-in-Docker with TLS:

```yaml
github-runner-smoke:
  stage: test
  image: docker:26.1.1
  tags:
    - mwcli-github-test
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

Click Play on the smoke job so it is pending. Then open **addshore/testing >
Actions > GitLab worker trial > Run workflow**, choosing `main`.

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

## Later automation

Once the smoke and real integration tests pass, add job-event webhook dispatch,
checks for still-pending jobs and required tags, duplicate protection, a bounded
worker pool and a periodic queue check for missed events. Move to the `mwcli` tag
only when ready to accept ordinary integration jobs. Run trusted workflow code
from `main`; keep runner-management credentials outside the privileged workers.

References:

- https://docs.gitlab.com/runner/commands/#gitlab-runner-run-single
- https://docs.gitlab.com/runner/commands/#gitlab-runner-unregister
- https://docs.gitlab.com/ci/docker/using_docker_build/#use-the-docker-executor-with-docker-in-docker
