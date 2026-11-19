vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Sync yank/paste with Android desktop clipboard (requires Termux:API app + termux-api pkg)
vim.opt.clipboard = "unnamedplus"

-- Keep undo history even after closing and reopening a file
vim.opt.undofile = true

-- Disable swap files (avoids "Swap file already exists" warnings on mobile/Termux)
vim.opt.swapfile = false

-- Keep 8 lines visible above/below the cursor when scrolling
vim.opt.scrolloff = 8

-- Highlight the line your cursor is currently on
vim.opt.cursorline = true

-- Always show the sign column (prevents screen jitter from git/error icons)
vim.opt.signcolumn = "yes"

-- Faster cursor hold events and key sequence timeouts (great for Termux)
vim.opt.updatetime = 250
vim.opt.timeoutlen = 400
