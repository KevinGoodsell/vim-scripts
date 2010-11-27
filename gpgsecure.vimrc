" Vim initialization file for use with gpgsecure.vim.
" Last Change: 2010 Nov 26
" Maintainer:  Kevin Goodsell <kevin-opensource@omegacrash.net>
" License:     GPL (see below)

" {{{ COPYRIGHT & LICENSE
"
" Copyright 2010 Kevin Goodsell
"
" This program is free software: you can redistribute it and/or modify it under
" the terms of the GNU General Public License as published by the Free Software
" Foundation, either version 3 of the License, or (at your option) any later
" version.
"
" This program is distributed in the hope that it will be useful, but WITHOUT
" ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
" FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
" details.
"
" You should have received a copy of the GNU General Public License along with
" this program.  If not, see <http://www.gnu.org/licenses/>.
"
" }}}
" {{{ NOTES
"
" This is just a replacement for .vimrc when using gpgsecure.vim. It should be
" used with the -u option to vim. It may be customized for individual needs.
"
" }}}

" loading_gpgsecure will cause the gpgsecure plugin to be loaded. It should
" also be used to conditionally enable/disable things in .vimrc or in plugins.
let g:loading_gpgsecure = 1

" Using -u to skip .vimrc causes 'compatible' to be set by default.
set nocompatible
" Don't automatically load plugins during startup.
set noloadplugins

" Don't load .vimrc by default. It's up to you to be sure that this is safe
" with your .vimrc. Use g:loading_gpgsecure to do things conditionally.
"if filereadable(expand("~/.vimrc")) | source ~/.vimrc | endif

" Load individual plugins. It's up to you to be sure that each of these is
" safe. Loading will look like this:
"runtime plugin/<script-name>.vim

" Load the gpgsecure plugin.
runtime plugin/gpgsecure.vim
