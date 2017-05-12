" Tslime.vim. Send portion of buffer to tmux instance
" Maintainer: Roger Jungemann <roger [at] thefifthcircuit [dot] com>
" Licence:    MIT

if exists("g:loaded_tslime") && g:loaded_tslime
  finish
endif

let g:loaded_tslime = 1

if !exists("g:tslime_ensure_trailing_newlines")
  let g:tslime_ensure_trailing_newlines = 0
endif
if !exists("g:tslime_normal_mapping")
  let g:tslime_normal_mapping = '<c-c><c-c>'
endif
if !exists("g:tslime_visual_mapping")
  let g:tslime_visual_mapping = '<c-c><c-c>'
endif
if !exists("g:tslime_vars_mapping")
  let g:tslime_vars_mapping = '<c-c>v'
endif
if !exists("g:tslime_entire_buffer_mapping")
  let g:tslime_entire_buffer_mapping = '<c-c>a'
endif

function! s:tmux_target()
  return '"' . g:tslime['session'] . '":' . g:tslime['window'] . "." . g:tslime['pane']
endfunction

function! s:set_tmux_buffer(text)
  let buf = substitute(a:text, "'", "\\'", 'g')
  call system("tmux load-buffer -", buf)
endfunction

function! s:ensure_newlines(text)
  let text = a:text
  let trailing_newlines = matchstr(text, '\v\n*$')
  let spaces_to_add = g:tslime_ensure_trailing_newlines - strlen(trailing_newlines)

  while spaces_to_add > 0
    let spaces_to_add -= 1
    let text .= "\n"
  endwhile

  return text
endfunction

function! Send_to_Tmux(text)
  if !exists("g:tslime")
    call <SID>Tmux_Vars()
  endif

  " Look, I know this is horrifying.  I'm sorry.
  "
  " THE PROBLEM: Certain REPLs (e.g.: SBCL) choke if you paste an assload of
  " text into them all at once (where 'assload' is 'something more than a few
  " hundred characters but fewer than eight thousand').  They'll seem to get out
  " of sync with the paste, and your code gets mangled.
  "
  " THE SOLUTION: We paste a single line at a time, and sleep for a bit in
  " between each one.  This gives the REPL time to process things and stay
  " caught up.  2 milliseconds seems to be enough of a sleep to avoid breaking
  " things and isn't too painful to sit through.
  "
  " This is my life.  This is computering in 2014.
  for line in split(a:text, '\n\zs' )
    call <SID>set_tmux_buffer(line)
    call system("tmux paste-buffer -dpt " . s:tmux_target())
    sleep 5m
  endfor
endfunction

" Session completion
function! Tmux_Session_Names(A,L,P)
  return <SID>TmuxSessions()
endfunction

" Window completion
function! Tmux_Window_Names(A,L,P)
  return <SID>TmuxWindows()
endfunction

" Pane completion
function! Tmux_Pane_Numbers(A,L,P)
  return <SID>TmuxPanes()
endfunction

function! s:ActiveTarget()
  return split(system('tmux list-panes -F "active=#{pane_active} #{session_name},#{window_index},#{pane_index}" | grep "active=1" | cut -d " " -f 2 | tr , "\n"'), '\n')
endfunction

function! s:TmuxSessions()
  if exists("g:tslime_always_current_session") && g:tslime_always_current_session
    let sessions = <SID>ActiveTarget()[0:0]
  else
    let sessions = split(system("tmux list-sessions -F '#{session_name}'"), '\n')
  endif
  return sessions
endfunction

function! s:TmuxWindows()
  if exists("g:tslime_always_current_window") && g:tslime_always_current_window
    let windows = <SID>ActiveTarget()[1:1]
  else
    let windows = split(system('tmux list-windows -F "#{window_index}" -t ' . g:tslime['session']), '\n')
  endif
  return windows
endfunction

function! s:TmuxPanes()
  let all_panes = split(system('tmux list-panes -t "' . g:tslime['session'] . '":' . g:tslime['window'] . " -F '#{pane_index}'"), '\n')

  " If we're in the active session & window, filter away current pane from
  " possibilities
  let active = <SID>ActiveTarget()
  let current = [g:tslime['session'], g:tslime['window']]
  if active[0:1] == current
    call filter(all_panes, 'v:val != ' . active[2])
  endif
  return all_panes
endfunction

" set tslime.vim variables
function! s:Tmux_Vars()
  let names = s:TmuxSessions()
  let g:tslime = {}
  if len(names) == 1
    let g:tslime['session'] = names[0]
  else
    let g:tslime['session'] = ''
  endif
  while g:tslime['session'] == ''
    let g:tslime['session'] = input("session name: ", "", "customlist,Tmux_Session_Names")
  endwhile

  let windows = s:TmuxWindows()
  if len(windows) == 1
    let window = windows[0]
  else
    let window = input("window name: ", "", "customlist,Tmux_Window_Names")
    if window == ''
      let window = windows[0]
    endif
  endif

  let g:tslime['window'] =  substitute(window, ":.*$" , '', 'g')

  let panes = s:TmuxPanes()
  if len(panes) == 1
    let g:tslime['pane'] = panes[0]
  else
    let g:tslime['pane'] = input("pane number: ", "", "customlist,Tmux_Pane_Numbers")
    if g:tslime['pane'] == ''
      let g:tslime['pane'] = panes[0]
    endif
  endif
endfunction

execute "vnoremap" . g:tslime_visual_mapping . ' "ry:call Send_to_Tmux(@r)<CR>'
execute "nnoremap" . g:tslime_normal_mapping . ' vip"ry:call Send_to_Tmux(@r)<CR>'
execute "nnoremap" . g:tslime_vars_mapping   . ' :call <SID>Tmux_Vars()<CR>'
execute "nnoremap" . g:tslime_entire_buffer_mapping . ' maggVG$"ry:call Send_to_Tmux(@r)<CR>`a'
