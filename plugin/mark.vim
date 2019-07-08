" Script Name: mark.vim
" Description: Highlight several words in different colors simultaneously. 
"
" Copyright:   (C) 2005-2008 by Yuheng Xie
"              (C) 2008-2011 by Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'. 
"
" Maintainer:  Ingo Karkat <ingo@karkat.de> 
"              modify by yangrz, base 2.51 version
"
" Avoid installing twice or when in unsupported Vim version. 
if exists('g:loaded_mark') || (v:version == 701 && ! exists('*matchadd')) || (v:version < 702)
	finish
endif
let g:loaded_mark = 1

"- functions ------------------------------------------------------------------
function! s:EscapeText( text )
	return substitute( escape(a:text, '\' . '^$.*[~'), "\n", '\\n', 'ge' )
endfunction

" Mark the current word, like the built-in star command. 
" If the cursor is on an existing mark, remove it. 
function! mark#MarkCurrentWord()
	let l:regexp = mark#CurrentMark()[0]
	if empty(l:regexp)
		let l:cword = expand('<cword>')
		if ! empty(l:cword)
			let l:regexp = s:EscapeText(l:cword)
			" The star command only creates a \<whole word\> search pattern if the
			" <cword> actually only consists of keyword characters. 
			if l:cword =~# '^\k\+$'
				let l:regexp = '\<' . l:regexp . '\>'
			endif
		endif
	endif

	if ! empty(l:regexp)
        let @/ = l:regexp
		call mark#DoMark(l:regexp)
	endif
endfunction

function! s:Cycle( ... )
	let l:currentCycle = s:cycle
	let l:newCycle = (a:0 ? a:1 : s:cycle) + 1
	let s:cycle = (l:newCycle < s:markNum ? l:newCycle : 0)
	return l:currentCycle
endfunction

" Set match / clear matches in the current window. 
function! s:MarkMatch( indices, expr )
	if ! exists('w:mwMatch') || len(w:mwMatch) == 0
		let w:mwMatch = repeat([0], s:markNum)
	endif

	for l:index in a:indices
		if w:mwMatch[l:index] > 0
			silent! call matchdelete(w:mwMatch[l:index])
			let w:mwMatch[l:index] = 0
		endif
	endfor

	if ! empty(a:expr)
		let l:index = a:indices[0]	" Can only set one index for now. 

		" Info: matchadd() does not consider the 'magic' (it's always on),
		" 'ignorecase' and 'smartcase' settings. 
		" Make the match according to the 'ignorecase' setting, like the star command. 
		" (But honor an explicit case-sensitive regexp via the /\C/ atom.) 
		let l:expr = ((&ignorecase && a:expr !~# '\\\@<!\\C') ? '\c' . a:expr : a:expr)

		" To avoid an arbitrary ordering of highlightings, we assign a different
		" priority based on the highlighting group, and ensure that the highest
		" priority is -10, so that we do not override the 'hlsearch' of 0, and still
		" allow other custom highlightings to sneak in between. 
		let l:priority = -10 - s:markNum + 1 + l:index

		let w:mwMatch[l:index] = matchadd('MarkWord' . (l:index + 1), l:expr, l:priority)
	endif
endfunction

" Initialize mark colors in a (new) window. 
function! mark#UpdateMark()
	let i = 0
	while i < s:markNum
		if ! s:enabled || empty(s:pattern[i])
			call s:MarkMatch([i], '')
		else
			call s:MarkMatch([i], s:pattern[i])
		endif
		let i += 1
	endwhile
endfunction

" Set / clear matches in all windows. 
function! s:MarkScope( indices, expr )
	let l:currentWinNr = winnr()

	" By entering a window, its height is potentially increased from 0 to 1 (the
	" minimum for the current window). To avoid any modification, save the window
	" sizes and restore them after visiting all windows. 
	let l:originalWindowLayout = winrestcmd() 

	noautocmd windo call s:MarkMatch(a:indices, a:expr)
	execute l:currentWinNr . 'wincmd w'
	silent! execute l:originalWindowLayout
endfunction

" Update matches in all windows. 
function! mark#UpdateScope()
	let l:currentWinNr = winnr()

	" By entering a window, its height is potentially increased from 0 to 1 (the
	" minimum for the current window). To avoid any modification, save the window
	" sizes and restore them after visiting all windows. 
	let l:originalWindowLayout = winrestcmd() 

	noautocmd windo call mark#UpdateMark()
	execute l:currentWinNr . 'wincmd w'
	silent! execute l:originalWindowLayout
endfunction

function! s:MarkEnable( enable, ...)
	if s:enabled != a:enable
		" En-/disable marks and perform a full refresh in all windows, unless
		" explicitly suppressed by passing in 0. 
		let s:enabled = a:enable
		
		if ! a:0 || ! a:1
			call mark#UpdateScope()
		endif
	endif
endfunction

function! s:EnableAndMarkScope( indices, expr )
	if s:enabled
		" Marks are already enabled, we just need to push the changes to all
		" windows. 
		call s:MarkScope(a:indices, a:expr)
	else
		call s:MarkEnable(1)
	endif
endfunction

" Toggle visibility of marks, like :nohlsearch does for the regular search
" highlighting. 
function! mark#Toggle()
	if s:enabled
		call s:MarkEnable(0)
		echo 'Disabled marks'
	else
		call s:MarkEnable(1)

		let l:markCnt = len(filter(copy(s:pattern), '! empty(v:val)'))
		echo 'Enabled' (l:markCnt > 0 ? l:markCnt . ' ' : '') . 'marks'
	endif
endfunction


" Mark or unmark a regular expression. 
function! s:SetPattern( index, pattern )
	let s:pattern[a:index] = a:pattern
endfunction

function! mark#ClearAll()
	let i = 0
	let indices = []
	while i < s:markNum
		if ! empty(s:pattern[i])
			call s:SetPattern(i, '')
			call add(indices, i)
		endif
		let i += 1
	endwhile
	let s:lastSearch = ''

" Re-enable marks; not strictly necessary, since all marks have just been
" cleared, and marks will be re-enabled, anyway, when the first mark is added.
" It's just more consistent for mark persistence. But save the full refresh, as
" we do the update ourselves. 
	call s:MarkEnable(0, 0)

	call s:MarkScope(l:indices, '')

	if len(indices) > 0
		echo 'Cleared all' len(indices) 'marks'
	else
		echo 'All marks cleared'
	endif
endfunction

function! mark#DoMark(...) " DoMark(regexp)
	let regexp = (a:0 ? a:1 : '')

	" Disable marks if regexp is empty. Otherwise, we will be either removing a
	" mark or adding one, so marks will be re-enabled. 
	if empty(regexp)
		call mark#Toggle()
		return
	endif

	" clear the mark if it has been marked
	let i = 0
	while i < s:markNum
		if regexp ==# s:pattern[i]
			if s:lastSearch ==# s:pattern[i]
				let s:lastSearch = ''
			endif
			call s:SetPattern(i, '')
			call s:EnableAndMarkScope([i], '')
			return
		endif
		let i += 1
	endwhile

	if s:markNum <= 0
		" Uh, somehow no mark highlightings were defined. Try to detect them again. 
		call mark#Init()
		if s:markNum <= 0
			" Still no mark highlightings; complain. 
			let v:errmsg = 'No mark highlightings defined'
			echohl ErrorMsg
			echomsg v:errmsg
			echohl None
			return
		endif
	endif

	" add to history
	if stridx(g:mwHistAdd, '/') >= 0
		call histadd('/', regexp)
	endif
	if stridx(g:mwHistAdd, '@') >= 0
		call histadd('@', regexp)
	endif

	" choose an unused mark group
	let i = 0
	while i < s:markNum
		if empty(s:pattern[i])
			call s:SetPattern(i, regexp)
			call s:Cycle(i)
			call s:EnableAndMarkScope([i], regexp)
			return
		endif
		let i += 1
	endwhile

	" choose a mark group by cycle
	let i = s:Cycle()
	if s:lastSearch ==# s:pattern[i]
		let s:lastSearch = ''
	endif
	call s:SetPattern(i, regexp)
	call s:EnableAndMarkScope([i], regexp)
endfunction

" Return [mark text, mark start position] of the mark under the cursor (or
" ['', []] if there is no mark). 
" The mark can include the trailing newline character that concludes the line,
" but marks that span multiple lines are not supported. 
function! mark#CurrentMark()
	let line = getline('.') . "\n"

	" Highlighting groups with higher numbers take precedence over lower numbers,
	" and therefore its marks appear "above" other marks. To retrieve the visible
	" mark in case of overlapping marks, we need to check from highest to lowest
	" highlighting group. 
	let i = s:markNum - 1
	while i >= 0
		if ! empty(s:pattern[i])
			" Note: col() is 1-based, all other indexes zero-based! 
			let start = 0
			while start >= 0 && start < strlen(line) && start < col('.')
				let b = match(line, s:pattern[i], start)
				let e = matchend(line, s:pattern[i], start)
				if b < col('.') && col('.') <= e
					return [s:pattern[i], [line('.'), (b + 1)]]
				endif
				if b == e
					break
				endif
				let start = e
			endwhile
		endif
		let i -= 1
	endwhile
	return ['', []]
endfunction

"- initializations ------------------------------------------------------------
augroup Mark
	autocmd!
	autocmd WinEnter * if ! exists('w:mwMatch') | call mark#UpdateMark() | endif
	autocmd TabEnter * call mark#UpdateScope()
augroup END

" Define global variables and initialize current scope.  
function! mark#Init()
	let s:markNum = 0
	while hlexists('MarkWord' . (s:markNum + 1))
		let s:markNum += 1
	endwhile
	let s:pattern = repeat([''], s:markNum)
	let s:cycle = 0
	let s:lastSearch = ''
	let s:enabled = 1
endfunction

"- configuration --------------------------------------------------------------
if ! exists('g:mwHistAdd')
	let g:mwHistAdd = '/@'
endif

call mark#Init()
call mark#UpdateScope()

"- default highlightings ------------------------------------------------------
function! s:DefaultHighlightings()
	" You may define your own colors in your vimrc file, in the form as below:
	highlight def MarkWord1  ctermbg=Red     ctermfg=White  guibg=Red      guifg=White
	highlight def MarkWord2  ctermbg=Yellow  ctermfg=Black  guibg=Yellow   guifg=Black
	highlight def MarkWord3  ctermbg=Blue    ctermfg=Black  guibg=Blue     guifg=Black
	highlight def MarkWord4  ctermbg=Green   ctermfg=Black  guibg=Green    guifg=Black
	highlight def MarkWord5  ctermbg=Magenta ctermfg=White  guibg=Magenta  guifg=White
	highlight def MarkWord6  ctermbg=Cyan    ctermfg=Black  guibg=Cyan     guifg=Black
	highlight def MarkWord7  ctermbg=Gray    ctermfg=Black  guibg=Gray     guifg=Black
	highlight def MarkWord8  ctermbg=Brown   ctermfg=Black  guibg=Brown    guifg=Black
endfunction

call s:DefaultHighlightings()
autocmd ColorScheme * call <SID>DefaultHighlightings()

"- mappings -------------------------------------------------------------------
nnoremap <silent> <Plug>MarkSet   :<C-u>call mark#MarkCurrentWord()<CR>:noh<CR>
nnoremap <silent> <Plug>MarkAllClear :<C-u>call mark#ClearAll()<CR>:noh<CR>

if !hasmapto('<Plug>MarkSet', 'n')
  nmap <unique> <silent> mm <Plug>MarkSet
  nmap <unique> <silent> mc <Plug>MarkAllClear
endif

command! -nargs=? Mark call mark#DoMark(<f-args>)
command! -bar MarkClear call mark#ClearAll()
