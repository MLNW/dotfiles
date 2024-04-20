#!/bin/bash

# Install plugins
# See: https://github.com/junegunn/vim-plug/issues/675#issuecomment-328157169
vim --not-a-term +'PlugInstall --sync' +qa
