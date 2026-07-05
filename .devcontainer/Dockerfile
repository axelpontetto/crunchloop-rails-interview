# [Choice] Ruby version (must satisfy Rails 7.1's >= 3.2.0 requirement): 3.3, 3.2, 3.3-bookworm, 3.2-bookworm
ARG VARIANT=3.3
FROM mcr.microsoft.com/devcontainers/ruby:${VARIANT}

# Rails itself is installed via `bundle install` (see postCreateCommand), which
# resolves the exact version pinned in Gemfile.lock. No global gem install needed.

# Default value to allow debug server to serve content over GitHub Codespace's port forwarding service
# The value is a comma-separated list of allowed domains 
ENV RAILS_DEVELOPMENT_HOSTS=".githubpreview.dev,.preview.app.github.dev"

# [Choice] Node.js version: lts/*, 16, 14, 12, 10
# ARG NODE_VERSION="none"
# RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && nvm install ${NODE_VERSION} 2>&1"

# [Optional] Uncomment this section to install additional OS packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>

# [Optional] Uncomment this line to install additional gems.
# RUN gem install <your-gem-names-here>

# [Optional] Uncomment this line to install global node packages.
# RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && npm install -g <your-package-here>" 2>&1
