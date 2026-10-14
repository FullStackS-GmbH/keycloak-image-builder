module.exports = {
  platform: 'gitlab',
  endpoint: 'https://gitlab.com/api/v4/',
  autodiscover: false,
  repositories: ['fullstacks-gmbh/cicd-components/keycloak'],
  onboarding: false,
  requireConfig: 'required',
  persistRepoData: false,
  allowedCommands: ['^bash scripts/render-component\\.sh$'],
};
