local util = require('nvim-treesitter.util')

local M = {}

---@class TSConfig
---@field auto_install boolean
---@field ensure_install string[]
---@field ignore_install string[]
---@field install_dir string

---@type TSConfig
local config = {
  auto_install = false,
  ensure_install = {},
  ignore_install = {},
  install_dir = vim.fs.joinpath(vim.fn.stdpath('data'), 'site'),
}

--- @param bufnr integer
local auto_install = util.throttle_by_id(function(bufnr)
  local ft = vim.bo[bufnr].filetype
  local lang = vim.treesitter.language.get_lang(ft) or ft
  if
    not require('nvim-treesitter.parsers').configs[lang]
    or vim.list_contains(M.installed_parsers(), lang)
    or vim.list_contains(config.ignore_install, lang)
  then
    return
  end

  local a = require('nvim-treesitter.async')
  local install = require('nvim-treesitter.install')
  a.run(function()
    if pcall(install._install, lang) then
      vim.treesitter.start(bufnr, lang)
    end
  end)
end)

---Setup call for users to override configuration configurations.
---@param user_data TSConfig|nil user configuration table
function M.setup(user_data)
  if user_data then
    if user_data.install_dir then
      user_data.install_dir = vim.fs.normalize(user_data.install_dir)
    end
    config = vim.tbl_deep_extend('force', config, user_data)
  end
  --TODO(clason): move to plugin/ or user config? only if non-default?
  vim.opt.runtimepath:append(config.install_dir)

  if config.auto_install then
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        auto_install(args.buf)
      end,
    })
  end

  if #config.ensure_install > 0 then
    local to_install = M.norm_languages(config.ensure_install, { ignored = true, installed = true })

    if #to_install > 0 then
      require('nvim-treesitter.install').install(to_install)
    end
  end
end

-- Returns the install path for parsers, parser info, and queries.
-- If the specified directory does not exist, it is created.
---@param dir_name string
---@return string
function M.get_install_dir(dir_name)
  local dir = vim.fs.joinpath(config.install_dir, dir_name)

  if not vim.uv.fs_stat(dir) then
    local ok, err = pcall(vim.fn.mkdir, dir, 'p', '0755')
    if not ok then
      local log = require('nvim-treesitter.log')
      log.error(err --[[@as string]])
    end
  end
  return dir
end

---@return string[]
function M.installed_parsers()
  local install_dir = M.get_install_dir('queries')

  local installed = {} --- @type string[]
  for f in vim.fs.dir(install_dir) do
    installed[#installed + 1] = f
  end

  return installed
end

---Normalize languages
---@param languages? string[]|string
---@param skip? table
---@return string[]
function M.norm_languages(languages, skip)
  if not languages then
    return {}
  end
  local parsers = require('nvim-treesitter.parsers')

  -- Turn into table
  if type(languages) == 'string' then
    languages = { languages }
  end

  if vim.list_contains(languages, 'all') then
    if skip and skip.missing then
      return M.installed_parsers()
    end
    languages = parsers.get_available()
  end

  for i, tier in ipairs(parsers.tiers) do
    if vim.list_contains(languages, tier) then
      languages = vim.iter.filter(function(l)
        return l ~= tier
      end, languages) --[[@as string[] ]]
      vim.list_extend(languages, parsers.get_available(i))
    end
  end

  if skip and skip.ignored then
    local ignored = config.ignore_install
    languages = vim.iter.filter(function(v)
      return not vim.list_contains(ignored, v)
    end, languages) --[[@as string[] ]]
  end

  if skip and skip.installed then
    local installed = M.installed_parsers()
    languages = vim.iter.filter(function(v)
      return not vim.list_contains(installed, v)
    end, languages) --[[@as string[] ]]
  end

  if skip and skip.missing then
    local installed = M.installed_parsers()
    languages = vim.iter.filter(function(v)
      return vim.list_contains(installed, v)
    end, languages) --[[@as string[] ]]
  end

  if not (skip and skip.dependencies) then
    for _, lang in pairs(languages) do
      if parsers.configs[lang].requires then
        vim.list_extend(languages, parsers.configs[lang].requires)
      end
    end
  end

  return languages
end

return M
