# Image w/ precompiled subkey binary
FROM --platform=linux/amd64 parity/subkey:latest AS subkey-bin
# DevContainer Image
FROM --platform=linux/amd64 mcr.microsoft.com/devcontainers/base:bookworm

# Install Node.js 22 and required tools
RUN apt-get update && \
    apt-get install -y curl wget git && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER vscode
ARG USER_HOME=/home/vscode
WORKDIR $USER_HOME

# Install Foundry and Polkadot tools
RUN curl -L https://raw.githubusercontent.com/paritytech/foundry-polkadot/refs/heads/master/foundryup/install | bash && \
    $USER_HOME/.foundry/bin/foundryup-polkadot

# Grab subkey binary from precompiled image
COPY --from=subkey-bin /usr/local/bin/subkey /usr/local/bin/

# Copy devtool scripts for container initialization and management
COPY --chmod=0755 ./scripts/devtool-scripts /usr/local/bin/devtool-scripts
COPY --chmod=0755 ./scripts/devtools.sh /usr/local/bin/devtools

# Switch back to root for system-level installations
USER root

# Install resolc, solc and Claude Code CLI
RUN npm install -g @parity/resolc && \
    npm install -g solc && \
    npm install -g @anthropic-ai/claude-code && \
    mkdir -p /commandhistory && chmod 777 /commandhistory && \
    mkdir -p $USER_HOME/.claude && chown vscode:vscode $USER_HOME/.claude

# Switch back to vscode user
USER vscode

# Setup aliases sourcing (actual file will be mounted)
RUN echo '[ -f ~/.bash_aliases ] && source ~/.bash_aliases' >> $USER_HOME/.bashrc

# Expose default Hardhat port (if running a local node)
EXPOSE 8545
