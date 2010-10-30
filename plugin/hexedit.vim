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

function! s:HexToggle()
    if !exists("b:hex_saved_ft")
        %!xxd -g1
        let b:hex_saved_ft = &filetype
        set filetype=xxd
    else
        %!xxd -r
        let &l:filetype = b:hex_saved_ft
        unlet b:hex_saved_ft
    endif
endfunction

command! -bar HexToggle call s:HexToggle()
