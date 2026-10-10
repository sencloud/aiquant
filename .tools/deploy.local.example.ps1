# Template for .tools\deploy.local.ps1 (the real file is gitignored).
#   Copy-Item .tools\deploy.local.example.ps1 .tools\deploy.local.ps1
# then fill in ONE auth method below. Never commit the filled-in copy.
# Environment variables (AIQUANT_DEPLOY_*) take precedence over this file.

# Non-secret overrides (leave empty to use the defaults in deploy.ps1)
$DeployHost    = ''
$DeployUser    = ''
$DeployHostkey = ''

# Recommended: SSH key auth. Path to a PuTTY private key (.ppk).
# Generate an OpenSSH key with ssh-keygen and convert it with puttygen, or
# create it directly with puttygen; put the public key in the server's
# ~/.ssh/authorized_keys. Once key login works, disable password login.
$DeployKeyFile = ''

# Fallback: password auth. Leave empty if you use a key.
$DeployPassword = ''
