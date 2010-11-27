" Vim global plugin for editing encrypted files.
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
" This is a basic plugin for securely editing files encrypted with GnuPG.
" Measures are taken to ensure that the plaintext file is not stored on disk.
" However, it's difficult to be sure that these measures are sufficient in all
" cases. Use with caution.
"
" This plugin lacks many of the features of gnupg.vim
" (http://www.vim.org/scripts/script.php?script_id=661), but it's simpler,
" seems to have fewer quirks, and most importantly does not store the
" plaintext in a temporary file when passing it to gpg.
"
" Because pipes are used to transfer the plaintext to gpg, and Vim only
" supports pipes on Unix systems, this plugin only works on Unix systems. On
" other systems it should give an error, rather than falling back on the
" insecure temp file method.
"
" The following options are used to help ensure security:
"
"   noshelltemp (global)
"     Don't write buffer to a temp file when passing text to external
"     programs.
"
"   viminfo= (global)
"     Don't store anything in the viminfo file. Avoids storing things like
"     yanked text.
"
"   noswapfile (buffer local)
"     Don't write buffer info to disk.
"
" }}}
" {{{ USAGE
"
" It's not safe to edit encrypted files containing sensitive information while
" using arbitrary plugins and scripts. For this reason, this plugin is not
" loaded by default. To use this plugin (more) safely, Vim should be invoked
" this way:
"
"   vim -u <path to gpgsecure.vimrc>
"
" gpgsecure.vimrc should be distributed with the plugin, and can be customized
" to suit your needs. Consider adding an alias like this to your shell startup
" file (.bashrc, etc.):
"
"   alias svim='vim -u ~/.vim/gpgsecure.vimrc'
"
" By default, your .vimrc file will not be loaded, since it may not be safe to
" do so. You can change this by editing gpgsecure.vimrc, and you can make your
" .vimrc safer by conditionally leaving out unsafe items when
" g:loading_gpgsecure is defined.
"
" In addition, all other plugins will be skipped by default. Plugins you feel
" are safe can be enabled on a case-by-case basis in gpgsecure.vimrc.
"
" If you want to simply use this as a normal plugin and bypass these extra
" security measures, you can define g:loading_gpgsecure in your .vimrc.
" Obviously this is not advised.
"
" Any use of this plugin is strictly at your own risk. As the license says,
" there is no warranty, explicit or implied.
"
" }}}
" {{{ SETTINGS
"
" The following settings are available:
"
"   g:gpg_options
"     A string with options that will be passed to gpg for encrypting and
"     decrypting. Default: "--use-agent"
"
"   g:gpg_read_options
"     A string with options that will be passed to gpg for decrypting.
"     Default: "--decrypt"
"
"   g:gpg_write_options
"     A string with options that will be passed to gpg for encrypting.
"     Default: "--symmetric"
"
" }}}

if exists("loaded_gpgsecure") || !exists("loading_gpgsecure")
    finish
endif
let loaded_gpgsecure = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists("g:gpg_options")
    let g:gpg_options = "--use-agent"
endif
if !exists("g:gpg_read_options")
    let g:gpg_read_options = "--decrypt"
endif
if !exists("g:gpg_write_options")
    let g:gpg_write_options = "--symmetric"
endif

augroup GpgSecure
    autocmd!
    autocmd BufReadCmd *.gpg call s:GpgRead(expand("<afile>"))
    autocmd BufWriteCmd *.gpg call s:GpgWrite(expand("<afile>"))
augroup END

function! s:ShellRead(cmd)
    return s:ShellCmd("read !" . a:cmd)
endfunction

function! s:ShellWrite(cmd)
    " This gives a Press Enter prompt unless silenced.
    return s:ShellCmd("silent write !" . a:cmd)
endfunction

function! s:ShellCmd(cmd)
    " Save stderr
    let temp = tempname()
    exec a:cmd . " 2> " . fnameescape(temp)
    let g:gpg_stderr = join(readfile(temp), "\n")
    call delete(temp)
    if v:shell_error != 0
        throw printf("shell error (%d): %s", v:shell_error, g:gpg_stderr)
    endif
endfunction

function! s:GpgRead(filename)
    try
        let file_exists = glob(a:filename, 1) != ""

        call s:SecuritySettings()
        setlocal buftype=acwrite

        if file_exists
            let saved_undolevels = &undolevels
            set undolevels=-1
            try
                call s:ShellRead(
                    \ printf("gpg --output - %s %s %s", g:gpg_options,
                           \ g:gpg_read_options, fnameescape(a:filename)))
                keepjumps 1 delete _
            finally
                let &undolevels = saved_undolevels
            endtry
        else
            " This causes the usual [New File] message.
            exec "edit " . fnameescape(a:filename)
        endif
    catch
        redraw
        echohl ErrorMsg
        echomsg v:exception
        echohl NONE
    endtry
endfunction

function! s:GpgWrite(filename)
    try
        let same_file = a:filename == expand("%")
        let overwrite = v:cmdbang || &writeany
        let file_exists = glob(a:filename, 1) != ""

        if !same_file && !overwrite && file_exists
            echoerr "File exists (add ! to override)"
            " As long as we're in a :try block, this return shouldn't actually
            " be needed, but it doesn't hurt.
            return
        endif

        call s:ShellWrite(printf("gpg %s %s > %s", g:gpg_options,
                               \ g:gpg_write_options, fnameescape(a:filename)))

        if same_file || &cpo =~ '\V+'
            setlocal nomodified
        endif
    catch
        redraw
        echohl ErrorMsg
        echomsg v:exception
        echohl NONE
    endtry
endfunction

function! s:SecuritySettings()
    " global settings
    if !has("filterpipe")
        throw "this Vim lacks the filterpipe feature required for secure " .
            \ "editing"
    endif
    set noshelltemp
    set viminfo=

    " local settings
    setlocal noswapfile
endfunction

let &cpo = s:save_cpo
