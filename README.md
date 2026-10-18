# testing

GitLab worker experiment (manual or webhook-triggered): [setup and smoke test](GITLAB-RUNNER-TRIAL.md).

The **GitLab clone test** workflow can be run manually to test public HTTPS cloning
of mwcli without registering a runner or using secrets. It tests anonymous access;
the GitLab smoke job also tests cloning with a CI job token.

Native GitHub integration experiment: [trial instructions](GITLAB-NATIVE-TRIAL.md).
