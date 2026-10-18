# Native GitHub integration trial

This runs mwcli's four Docker integration tests as native GitHub Actions jobs.
It does not install or register GitLab Runner. Production CI is unchanged.

Start with **Native GitLab bridge checks** in Actions. This requires no secrets:
it tests callbacks, retries, result receipts and native execution with local
fixtures. It does not run the real Docker integration tests or write to GitLab.

For the full round trip:

1. Set this repository's `GITLAB_STATUS_TOKEN` secret to a temporary project-16
   access token with Maintainer role and `api` scope. The old `read_api` token
   cannot post statuses or play the verification job. Set `GITLAB_NATIVE_ENABLED`
   to `true` in Actions repository variables.
2. Set `GITHUB_STATUS_BOT_ID` in GitLab to that token bot's numeric user ID. This
   is nonsecret and must be available to MR pipelines, so leave Protected off.
3. Push the local `github-native-integration-trial` branch to Wikimedia GitLab
   and open a **draft** MR targeting `main`. Do not merge it. Only this branch
   sets `GITHUB_NATIVE_INTEGRATION=1` and selects `addshore/testing`.
4. Wait for `integration-github-request` to succeed and copy its numeric job ID.
5. Run **GitLab native integration** here manually on `main`, with project `16`,
   that job ID, job name `integration-github-request` and status `success`.
6. Verify that four `github/*` results appear in that GitLab pipeline, each
   linking to its native GitHub job log. The blocking `integration-github` job
   should start automatically and pass only when all four tests pass.

Use Re-run failed jobs in GitHub to retry tests and refresh the GitLab results.
Do not play the GitLab verification job yourself: it requires the reporting bot
as its issuer. If another user plays it, start a new GitLab pipeline.

After the manual round trip works, a separate GitLab Job events webhook can
exercise automatic dispatch. Its URL is:

```text
https://api.github.com/repos/addshore/testing/actions/workflows/gitlab-integration.yml/dispatches
```

Use a custom Authorization header with a GitHub fine-grained token restricted
to this repository and Actions read/write. Use this custom request body:

```json
{"ref":"main","inputs":{"project_id":"{{project_id}}","job_id":"{{build_id}}","job_name":"{{build_name}}","job_status":"{{build_status}}"}}
```

Keep the existing production webhook and runners unchanged. Disable the trial
webhook and `GITLAB_NATIVE_ENABLED`, revoke the temporary token and remove or
replace its GitLab bot ID when the trial finishes.

For a controlled failure/retry test, set the Actions repository variable
`GITLAB_TRIAL_FAIL_TEST` to `mysql-cycle` before dispatching. The workflow will
run the real test, then deliberately fail that native job. Verify the GitLab
status and gate fail, delete the variable, and use Re-run failed jobs in GitHub.
This injection exists only in this testing repository's reusable workflow.
