" Vim global plugin to fix certain terminals.
" Last Change: 2011 Apr 17
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
" This plugin attempts to fix up Vim's support for certain terminals.
" Currently this means enabling more terminal keys, including with modifier
" keys. Currently supported terminals are:
"
"   GNOME Terminal
"   xterm
"   rxvt
"   Screen or tmux running on any of the above
"
" The plugin attempts to automatically detect the underlying terminal, but you
" can also specify the terminal if detection doesn't work.
"
" }}}
" {{{ OPTIONS
"
"   g:termfix_term
"
"     This is a string that identifies the terminal type. Auto-detection is
"     used if this is 'AUTO' (the default). This doesn't generally need to be
"     a precise terminal name, it just needs to start with 'xterm', 'rxvt',
"     'gnome', or whatever.
"
"  g:termfix_multiplexer
"
"    This is a string that identifies the terminal multiplexer being used. It
"    should be 'screen' for either GNU Screen or tmux, empty for none, or
"    'AUTO' (the default) for auto-detection.
"
"  g:termfix_map
"
"    This determines whether mappings are used for key combinations when
"    settings aren't available. If 0, no mappings will be used (making some
"    keys or combinations unavailable). If non-zero, mappings will be used
"    when they are the only option. Some terminals need a lot of mappings, and
"    can make the :map and :map! output very messy. Mappings are used by
"    default.
"
"  g:termfix_testing
"
"    If this evaluates as true, extra features for testing are enabled.
"    Generally intended for development use only.
"
" }}}

if exists("loaded_termfix")
    finish
endif
let loaded_termfix = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists("g:termfix_term")
    let g:termfix_term = "AUTO"
endif

" Should be 'screen' for Screen or tmux.
if !exists("g:termfix_multiplexer")
    let g:termfix_multiplexer = "AUTO"
endif

" Use :map when :set isn't possible?
if !exists("g:termfix_map")
    let g:termfix_map = 1
endif

if !exists("g:termfix_testing")
    let g:termfix_testing = 0
endif

let s:termfix_mappings = []

function! s:MapKey(symbol, code)
    if g:termfix_map
        exec printf("map %s <%s>", a:code, a:symbol)
        exec printf("map! %s <%s>", a:code, a:symbol)
        call add(s:termfix_mappings, a:code)
    endif
endfunction

" Set up mapped keys for rxvt-style modifiers. The last character is:
" ~ : no modifier
" $ : Shift
" ^ : Ctrl
" @ : Shift + Ctrl
" The extra argument is a string to specify which versions to map. Each char
" is a version: - for no modifier, S for Shift, C for Ctrl, H for Shift+Ctrl.
" Defaults to 'SCH' for Shift, Ctrl, and Shift+Ctrl.
function! s:MapRxvtMod(symbol, code, ...)
    if a:0 == 0
        let mods = ["S", "C", "H"]
    else
        let mods = split(a:1, '\zs')
    endif
    let prefixes = {"-" : ["", "~"], "S" : ["S-", "$"], "C" : ["C-", "^"],
                  \ "H" : ["S-C-", "@"]}
    for mod in mods
        let [prefix, suffix] = prefixes[mod]
        call s:MapKey(prefix . a:symbol, a:code . suffix)
    endfor
endfunction

function! s:ClearMappings()
    for code in s:termfix_mappings
        exec "unmap " . code
        exec "unmap! " . code
    endfor

    let s:termfix_mappings = []
endfunction

function! s:SetupTerm(term, multiplexer)
    " Screen codes use the extended keys (like <xEnd>) when possible. Since
    " Screen doesn't handle modifier keys, modifier-supporting codes from
    " other terminals should always use the primary key (like <End>), or
    " possibly the tertiary key when there is one (like <zEnd>). misc2.c
    " key_names_table has all of these, and modifier_keys_table shows
    " available modifiers.
    if a:multiplexer =~# '\v^screen'
        " This is using 'application mode' keys, which is probably what will
        " usually be used in Vim.
        exec "set <xUp>=\eOA"
        exec "set <xDown>=\eOB"
        exec "set <xRight>=\eOC"
        exec "set <xLeft>=\eOD"
        exec "set <xHome>=\e[1;*~"
        exec "set <xEnd>=\e[4;*~"
        exec "set <xF1>=\eOP"
        exec "set <xF2>=\eOQ"
        exec "set <xF3>=\eOR"
        exec "set <xF4>=\eOS"
    endif

    if a:term =~# '\v^(gnome|xterm)'
        exec "set <Up>=\e[1;*A"
        exec "set <Down>=\e[1;*B"
        exec "set <Right>=\e[1;*C"
        exec "set <Left>=\e[1;*D"
        exec "set <End>=\e[1;*F"
        exec "set <Home>=\e[1;*H"
        exec "set <Insert>=\e[2;*~"
        exec "set <Del>=\e[3;*~"
        exec "set <PageUp>=\e[5;*~"
        exec "set <PageDown>=\e[6;*~"

        if a:term =~# '\v^gnome'
            exec "set <F1>=\eO1;*P"
            exec "set <F2>=\eO1;*Q"
            exec "set <F3>=\eO1;*R"
            exec "set <F4>=\eO1;*S"
        elseif a:term =~# '\v^xterm'
            exec "set <F1>=\e[1;*P"
            exec "set <F2>=\e[1;*Q"
            exec "set <F3>=\e[1;*R"
            exec "set <F4>=\e[1;*S"
        endif

        exec "set <F5>=\e[15;*~"
        exec "set <F6>=\e[17;*~"
        exec "set <F7>=\e[18;*~"
        exec "set <F8>=\e[19;*~"
        exec "set <F9>=\e[20;*~"
        exec "set <F10>=\e[21;*~"
        exec "set <F11>=\e[23;*~"
        exec "set <F12>=\e[24;*~"

        if a:multiplexer == ""
            exec "set <xUp>=\eOA"
            exec "set <xDown>=\eOB"
            exec "set <xRight>=\eOC"
            exec "set <xLeft>=\eOD"
            exec "set <xEnd>=\eOF"
            exec "set <xHome>=\eOH"
            exec "set <xF1>=\eOP"
            exec "set <xF2>=\eOQ"
            exec "set <xF3>=\eOR"
            exec "set <xF4>=\eOS"
        endif

    elseif a:term =~# '\v^linux'
        exec "set <S-F1>=\e[25~"
        exec "set <S-F2>=\e[26~"
        exec "set <S-F3>=\e[28~"
        exec "set <S-F4>=\e[29~"
        exec "set <S-F5>=\e[31~"
        exec "set <S-F6>=\e[32~"
        exec "set <S-F7>=\e[33~"
        exec "set <S-F8>=\e[34~"

    elseif a:term =~# '\v^rxvt'
        " Shift & Ctrl arrow keys. Shift+Ctrl is the same as Shift alone.
        exec "set <S-Up>=\e[a"
        exec "set <S-Down>=\e[b"
        exec "set <S-Right>=\e[c"
        exec "set <S-Left>=\e[d"

        call s:MapKey("C-Up", "\eOa")
        call s:MapKey("C-Down", "\eOb")
        exec "set <C-Right>=\eOc"
        exec "set <C-Left>=\eOd"

        " S-Insert seems to not be passed to the application, but it doesn't
        " hurt to include it.
        exec "set <S-Insert>=\e[2$"
        exec "set <S-Del>=\e[3$"
        exec "set <S-Home>=\e[7$"
        exec "set <S-End>=\e[8$"
        exec "set <C-Home>=\e[7^"
        exec "set <C-End>=\e[8^"

        " Fill in the rest with mappings
        call s:MapRxvtMod("Insert", "\e[2", "CH")
        call s:MapRxvtMod("Del", "\e[3", "CH")
        " S-PageUp and S-PageDown aren't passed to the app.
        call s:MapRxvtMod("PageUp", "\e[5", "CH")
        call s:MapRxvtMod("PageDown", "\e[6", "CH")
        call s:MapKey("C-S-Home", "\e[7@")
        call s:MapKey("C-S-End", "\e[8@")

        " Function keys are a little weird. S-F1 to S-F10 are F11 to F20, so
        " there's no shifted F1-F10, there *is* a shifted F11 and F12, then
        " there's no shifted F13-F20.

        " Vim's builtin xterm settings map <Undo> and <Help> in a way that
        " conflicts with rxvt's F14 and F15.
        set <Undo>=
        set <Help>=

        " F13-F20 and the 2 available shifted function keys have settings.
        " The rest need mappings.
        exec "set <F13>=\e[25~"
        exec "set <F14>=\e[26~"
        exec "set <F15>=\e[28~"
        exec "set <F16>=\e[29~"
        exec "set <F17>=\e[31~"
        exec "set <F18>=\e[32~"
        exec "set <F19>=\e[33~"
        exec "set <F20>=\e[34~"
        exec "set <S-F11>=\e[23$"
        exec "set <S-F12>=\e[24$"

        call s:MapKey("C-F1", "\e[11^")
        call s:MapKey("C-F2", "\e[12^")
        call s:MapKey("C-F3", "\e[13^")
        call s:MapKey("C-F4", "\e[14^")
        call s:MapKey("C-F5", "\e[15^")
        call s:MapKey("C-F6", "\e[17^")
        call s:MapKey("C-F7", "\e[18^")
        call s:MapKey("C-F8", "\e[19^")
        call s:MapKey("C-F9", "\e[20^")
        call s:MapKey("C-F10", "\e[21^")
        call s:MapRxvtMod("F11", "\e[23", "CH")
        call s:MapRxvtMod("F12", "\e[24", "CH")
        call s:MapRxvtMod("F13", "\e[25", "C")
        call s:MapRxvtMod("F14", "\e[26", "C")
        call s:MapRxvtMod("F15", "\e[28", "C")
        call s:MapRxvtMod("F16", "\e[29", "C")
        call s:MapRxvtMod("F17", "\e[31", "C")
        call s:MapRxvtMod("F18", "\e[32", "C")
        call s:MapRxvtMod("F19", "\e[33", "C")
        call s:MapRxvtMod("F20", "\e[34", "C")
    endif
endfunction

function! s:FixTerm()
    if has("gui_running")
        return
    endif

    call s:ClearMappings()

    if &term =~# '\v^screen'
        if g:termfix_multiplexer == "AUTO"
            let g:termfix_multiplexer = "screen"
        endif
        if g:termfix_term == "AUTO"
            if &term =~# '\v^screen\.'
                let g:termfix_term = matchstr(&term, '\v^screen\.\zs.*')
            elseif !empty($COLORTERM)
                let g:termfix_term = $COLORTERM
            elseif !empty($XTERM_VERSION)
                let g:termfix_term = "xterm"
            else
                let g:termfix_term = ""
            endif
        endif
    else
        if g:termfix_multiplexer == "AUTO"
            let g:termfix_multiplexer = ""
        endif
        if g:termfix_term == "AUTO"
            let g:termfix_term = &term
        endif
    endif

    call s:SetupTerm(g:termfix_term, g:termfix_multiplexer)
endfunction

augroup TermFix
    au!
    au TermChanged,VimEnter * call s:FixTerm()
augroup END

if g:termfix_testing
    " This adds imap mappings for the function and application keys, causing
    " them to ouput their own 'name'. Offers a quick way to test how keys have
    " been mapped. Must be called manually to set up the mappings.
    function! g:TermfixMapKeys()
        let fkeys = map(range(1, 20), '"F" . v:val')
        let keys = fkeys + ["Up", "Down", "Right", "Left", "Del", "Insert",
            \ "PageUp", "PageDown", "Home", "End"]
        let mods = ["", "S-", "C-", "M-", "S-C-", "C-M-", "S-M-", "C-S-M-"]

        for key in keys
            for mod in mods
                let combined = mod . key
                exec printf("imap <%s> <lt>%s>", combined, combined)
            endfor
        endfor
    endfunction
endif

let &cpo = s:save_cpo
