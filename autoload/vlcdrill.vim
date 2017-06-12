"Symbols/Constants. Can expose as settings later if needed
let s:DRILL_BUF_NAME = "__VlcDrill__"
let s:TELNET_PORT = 4212
let s:TELNET_PASSWORD = "test"
let s:LOG_LOCATION = "$HOME/.vlc_drill.log"
"set to 1 to echo telnet commands into :messages as well
let s:DEBUG_FLAG = 0

"Defaults
if !exists("g:vlcdrill#bin#path")
    let g:vlcdrill#bin#path = 'vlc'
endif
let s:current_directory = expand("<sfile>:p:h")
if !exists("g:vlcdrill#annotation#path")
    let g:vlcdrill#annotation#path = s:current_directory . '/../example_annotations/aimee_mann_youtube.json'
endif


"helpers
"------------
"Lib
"----
"0 → 0:00
"30 → 0:30
"70 → 1:30 etc.
function! s:SecondsToDisplay(seconds)
    let internal = {}
    function internal.padLeft(digit)
        if a:digit >= 10
            return a:digit
        else
            return '0' . a:digit
        endif
    endfunction

    let minutes = a:seconds/60
    let seconds = a:seconds%60
    return minutes . ':' . internal.padLeft(seconds)
endfunction

"UI
"----
" [<string>] → ()
function! s:renderToCurrentBuffer(lines) abort
    "https://vi.stackexchange.com/questions/7761/how-to-restore-the-position-of-the-cursor-after-executing-a-normal-command/10700
    let save_pos = getpos('.')
    setlocal modifiable
    silent 1,$delete _
    call append(0, a:lines)
    "seems to carry a blank line at the end; trim that off
    silent $delete _
    setlocal nomodifiable
    call setpos('.', save_pos)
endfunction

function! s:setDrillBufferSettings() abort
    "buffer
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal nobuflisted
    setlocal nomodifiable
    setlocal filetype=vlcdrill
    setlocal nolist
    setlocal nonumber
    setlocal norelativenumber
    setlocal nowrap

    "syntax
    let b:current_syntax = 'vlcdrill'
    syntax match VlcDrillHeading '^------.*------$'
    syntax match VlcDrillPlaying '\v^▌.*$'
    syntax match VlcDrillHelpKeyAlpha '\v^\zs[a-z][a-z]?\ze(\s|:)'
    syntax match VlcDrillHelpKeyNonAlpha '\v^\zs\<\w*\>\ze:'
    highlight def link VlcDrillHeading String
    highlight def link VlcDrillPlaying Keyword
    highlight def link VlcDrillHelpKeyAlpha Type
    highlight def link VlcDrillHelpKeyNonAlpha Type

    "mappings
    
    "rate
    nnoremap <script> <silent> <buffer> ri :call <SID>VlcDrillRateIncrease()<CR>
    nnoremap <script> <silent> <buffer> rd :call <SID>VlcDrillRateDecrease()<CR>
    nnoremap <script> <silent> <buffer> rn :call <SID>VlcDrillRateNormal()<CR>

    "quit
    nnoremap <script> <silent> <buffer> q :call <SID>VlcDrillClose()<CR>
    "play
    nnoremap <script> <silent> <buffer> p :call <SID>VlcDrillPlay()<CR>
    vnoremap <script> <silent> <buffer> p :call <SID>VlcDrillPlayFromLinewise()<CR>
    "lOop
    nnoremap <script> <silent> <buffer> o :call <SID>VlcDrillToggleLoop()<CR>
    "get cUrrent Time
    nnoremap <script> <silent> <buffer> u :call <SID>VlcDrillGetCurrentTime()<CR>

    nnoremap <script> <silent> <buffer> <Space> :call <SID>VlcDrillTogglePause()<CR>
    nnoremap <script> <silent> <buffer> <Down> :call <SID>VlcDrillVolDown()<CR>
    nnoremap <script> <silent> <buffer> <Up> :call <SID>VlcDrillVolUp()<CR>
    nnoremap <script> <silent> <buffer> <Left> :call <SID>VlcDrillPrev()<CR>
    nnoremap <script> <silent> <buffer> <Right> :call <SID>VlcDrillNext()<CR>

    nnoremap <script> <silent> <buffer> <leader>d :call <SID>VlcDrillDebug()<CR>
endfunction

"telnet/rc command builders
function! s:isTelnetServerStarted(port) abort
    let started = system('lsof -i:' . a:port)
    return strlen(started)
endfunction

function! s:startTelnetServer(vlc_bin, port, password, log_location) abort
    let pushed_shellcmdflags = &shellcmdflag
    set shellcmdflag=-ic
    " http://stackoverflow.com/questions/2292847/how-to-silence-output-in-a-bash-script
    "silent execute "!" . a:vlc_bin . " -I telnet --telnet-password " . a:password . " > " . a:log_location . " 2>&1 &"
    "redraw!
    call system(a:vlc_bin . " -I telnet --telnet-password " . a:password . " > " . a:log_location . " 2>&1 &")
    let &shellcmdflag=pushed_shellcmdflags
endfunction

"curry off the port and password
function! s:TelnetCommandBuilder(port, password) abort
    let builder = {}
    function builder.build(rc_command) closure
        return "echo -e '" . a:password . "\\n" . a:rc_command . "' | nc localhost " . a:port
    endfunction
    return builder
endfunction

"indexes the playlist:
"<AnnotationSpec> → {
"   by_lines <{line_num <int> → {type, song_id, start_time?, description?}}>
"   by_song_id <{song_id <int> → {title?, stream}}>
"}
"where type = song | section
"UI and line interpreter uses the `by_lines` index
"by_song_id may also be used if line is interpreted as a section
function! s:indexAnnotation(annotation) abort
    let line_num = 1
    let song_id = 0
    let indexed = {}
    let indexed.by_lines = {}
    let indexed.by_song_id = {}

    for song in a:annotation.playlist
        let indexed.by_lines[line_num] = {
                    \ 'type': 'song',
                    \ 'song_id': song_id,
                    \ 'start_time': 0
                    \}
        let line_num = line_num + 1
        if type(song) ==# v:t_string
            let indexed.by_song_id[song_id] = {
                        \ 'title': song,
                        \ 'stream': song
                        \}
        elseif type(song) ==# v:t_dict
            let indexed.by_song_id[song_id] = {
                        \ 'title': song.title,
                        \ 'stream': song.stream
                        \}
            if (has_key(song, 'sections'))
                for section in song.sections
                    if (type(section) ==# v:t_list)
                        let start_time = section[0]
                        let description = section[1]
                        let indexed.by_lines[line_num] = {
                                    \ 'type': 'section',
                                    \ 'song_id': song_id,
                                    \ 'description': description,
                                    \ 'start_time': start_time
                                    \}
                    elseif (type(section) ==# v:t_number)
                        let start_time = section
                        let indexed.by_lines[line_num] = {
                                    \ 'type': 'section',
                                    \ 'song_id': song_id,
                                    \ 'start_time': start_time
                                    \}
                    else
                        echoerr "unrecognised format; section must be either seconds<number> or [seconds<number>, description<string>]"
                    endif
                    let line_num = line_num + 1
                endfor
            endif
        endif
        let song_id = song_id + 1
    endfor
    return indexed
endfunction

function! s:matchRawRc(raw_status) abort
    return matchstr(a:raw_status, '\vWelcome, Master%x0d%x00\zs.*\ze%x0d%x00\> Bye-bye!')
endfunction!

function! s:matchRawStatus(raw_status) abort
    let raw_rc = s:matchRawRc(a:raw_status)
    let volume = matchstr(raw_rc, '\v\( audio volume: \zs[0-9]+\ze \)')
    let state = matchstr(raw_rc, '\v\( state \zs[a-z]+\ze \)')
    return [volume, state]
endfunction

"{
"   by_lines <{line_num <int> → {type, song_id, start_time?, description?}}>
"   by_song_id <{song_id <string> → {stream}}>
"}, [{title <string>, sections?}...], {title<string>?, volume<int>?, state<playing|paused|stopped>?} → ()
"where sections = <int> | [<int>, <string>]
"where type = song | section
function! s:renderInterface(indexed_annotation, state) abort
    let by_lines = a:indexed_annotation.by_lines
    let by_song_id = a:indexed_annotation.by_song_id
    "internal functions
    let internal = {}
    function internal.shouldRenderInPlaylist(line_num) closure
        if a:state.linewise_mode ==# 1
            if a:line_num >= a:state.line_selected[0] && a:line_num <= a:state.line_selected[1]
                return 1
            else
                return 0
            endif
        else "regular play mode
            let line = by_lines[a:line_num]
            if has_key(a:state, 'line_selected')
                let current_song_id = by_lines[a:state.line_selected].song_id
                let current_song_type = by_lines[a:state.line_selected].type
                if current_song_type ==# 'song' && line.song_id ==# current_song_id
                    return 1
                "elseif current_song_type ==# 'section' && a:line_num ==# a:state.line_selected
                elseif current_song_type ==# 'section' && line.song_id ==# current_song_id && a:line_num >= a:state.line_selected
                    return 1
                else
                    return 0
                endif
            else
                return 0
            endif
        endif
    endfunction
    function internal.shouldRenderLoop(line_num) closure
        if a:state.linewise_mode ==# 1
            if a:line_num >= a:state.line_selected[0] && a:line_num <= a:state.line_selected[1]
                return 1
            else
                return 0
            endif
        else "regular play mode
            let line = by_lines[a:line_num]
            if has_key(a:state, 'line_selected')
                let current_song_id = by_lines[a:state.line_selected].song_id
                let current_song_type = by_lines[a:state.line_selected].type
                if current_song_type ==# 'song' && line.song_id ==# current_song_id && a:state.loop ==# 1
                    return 1
                elseif current_song_type ==# 'section' && line.song_id ==# current_song_id && a:line_num >= a:state.line_selected && a:state.loop ==# 1
                    return 1
                else
                    return 0
                endif
            else
                return 0
            endif
        endif
    endfunction
    function internal.shouldRenderPlayPauseIndicator(line_num) closure
        if has_key(a:state, 'line_selected')
            if type(a:state.line_selected) ==# v:t_list
                if a:line_num ==# a:state.line_selected[0]
                    return 1
                else
                    return 0
                endif
            elseif type(a:state.line_selected) ==# v:t_number
                if a:line_num ==# a:state.line_selected
                    return 1
                else
                    return 0
                endif
            else
                return 0
            endif
        else
            return 0
        endif
    endfunction
    function internal.generateLeftPlaylistIndicatorFragment(line_num)
        let template = ''
        if self.shouldRenderInPlaylist(a:line_num)
            let template = template . '▌'
        else
            let template = template . ' '
        endif
        if self.shouldRenderLoop(a:line_num)
            let template = template . '-'
        else
            let template = template . ' '
        endif
        let template = template . ' '
        return template
    endfunction
    function internal.generatePlayPauseFragment() closure
        if a:state.play_state ==# 'playing'
            return ' ▶'
        elseif a:state.play_state ==# 'paused'
            return ' ⏸'
        else
            return ''
        endif
    endfunction
    function internal.SongTemplate(line_num) closure
        let line = by_lines[a:line_num]
        let song = by_song_id[line.song_id]
        let template = internal.generateLeftPlaylistIndicatorFragment(a:line_num)
        let template = template . song.title . "  " . s:SecondsToDisplay(line.start_time)
        if self.shouldRenderPlayPauseIndicator(a:line_num)
            let template = template . internal.generatePlayPauseFragment()
        endif
        return template
    endfunction
    function internal.SectionTemplate(line_num) closure
        let line = by_lines[a:line_num]
        let template = internal.generateLeftPlaylistIndicatorFragment(a:line_num)
        if has_key(line, 'description')
            let template = template . "  " . line.description . "  " . s:SecondsToDisplay(line.start_time)
        else
            let template = template . "  " . s:SecondsToDisplay(line.start_time)
        endif
        if internal.shouldRenderPlayPauseIndicator(a:line_num)
            let template = template . internal.generatePlayPauseFragment()
        endif
        return template
    endfunction

    let by_lines = a:indexed_annotation.by_lines
    let ui = []
    for line_num in sort(keys(by_lines), 'N')
        let line = by_lines[line_num]
        if line.type ==# 'song'
            call add(ui, internal.SongTemplate(line_num))
        elseif line.type ==# 'section'
            call add(ui, internal.SectionTemplate(line_num))
        endif
    endfor

    "divider
    call add(ui, "")
    call add(ui, "------Status------")

    "state
    if has_key(a:state, 'play_state')
        call add(ui, "State: " . a:state.play_state)
    endif
    if has_key(a:state, 'volume')
        call add(ui, "Volume: " . a:state.volume)
    endif
    if has_key(a:state, 'loop')
        call add(ui, "Loop On: " . (a:state.loop ? 'True' : 'False'))
    endif
    if has_key(a:state, 'rate')
        call add(ui, "Rate: " . string(a:state.rate/10.0))
    endif
    if has_key(a:state, 'current_time')
        let current_time = a:state.current_time[0]
        let total_time = a:state.current_time[1]
        call add(ui, "Last Time Requested: " . s:SecondsToDisplay(current_time) . '/' . s:SecondsToDisplay(total_time))
    endif

    "help
    "call add(ui, "")
    "call add(ui, "------Manual------")

    "call add(ui, "▌: indicates that section is selected")
    "call add(ui, "▌-: indicates that section is on selected and on loop")
    "call add(ui, "▶/⏸ : indicates current")

    call add(ui, "")
    call add(ui, "------Bindings------")

    call add(ui, "<Up>: volume up")
    call add(ui, "<Down>: volume down")
    call add(ui, "<Space>: toggle play/pause")
    call add(ui, "<Left>: previous VLC playlist item in selection")
    call add(ui, "<Right>: next VLC playlist item in selection")
    call add(ui, "p (normal mode): play section under cursor till end of its stream")
    call add(ui, "p (linewise visual mode): loop highlighted section(s)")
    call add(ui, "ri: increase rate")
    call add(ui, "rd: decrease rate")
    call add(ui, "rn: normal rate")
    call add(ui, "u: show seconds played of stream")
    call add(ui, "o: toggle loop")
    call add(ui, "q: close VlcDrill buffer")

    "paint to buffer
    call s:openInterface()
    call s:renderToCurrentBuffer(ui)
endfunction

function! s:IsLinewiseSelection(currently_visual)
    if a:currently_visual
        let start_pos = getpos("'<")
        let end_pos = getpos("'>")
        "Note that for '< and '> Visual mode matters: when it is "V" "(visual line mode) the column of '< is zero and the column of "'> is a large number.
        let col1 = start_pos[2]
        let col2 = end_pos[2]
        return col1 ==# 1 && col2 > 1000 "hoping that 1000 is sufficiently large
    else
        return 0
    endif
endfunction

function! s:ExecuteSilently(command, debug_flag)
    if a:debug_flag ==# 1
        echom a:command
    endif
    return system(a:command)
endfunction

function! s:DrillInterface(telnet_port, telnet_password, log_location, debug_flag) abort

    let annotation_loaded = 0
    let indexed_annotation = {} "to be set on loadAnnotation
    "line_selected <int>
    "current_time [current_time <int>, total_time <int>]
    let state = {
                \'loop': 0,
                \'linewise_mode': 0,
                \'rate': 10
                \}
    let tcb = s:TelnetCommandBuilder(a:telnet_port, a:telnet_password)
    
    "internal functions
    let internal = {}
    function internal.getState() closure
        if s:isTelnetServerStarted(a:telnet_port) ==# 0
            return state
        else
            let raw_status = system(tcb.build('status'))
            let [volume, play_state] = s:matchRawStatus(raw_status)
            let title = s:matchRawRc(system(tcb.build('get_title')))
            let state_for_ui = {
                        \'loop': state.loop,
                        \'rate': state.rate,
                        \'linewise_mode': state.linewise_mode,
                        \'volume': volume,
                        \'play_state': play_state,
                        \'title': title
                        \}
            if has_key(state, 'line_selected')
                let state_for_ui.line_selected = state.line_selected
            endif
            if has_key(state, 'current_time')
                let state_for_ui.current_time = state.current_time
            endif
            return state_for_ui
        endif
    endfunction
    function internal.interpretLinesToPlay(first_line, last_line, currently_visual) closure
        if s:IsLinewiseSelection(a:currently_visual) "visual linemode check
            if has_key(indexed_annotation.by_lines, a:first_line) && has_key(indexed_annotation.by_lines, a:last_line)
                let state.line_selected = [a:first_line, a:last_line]
                " checking boundaries on the song
                if (a:first_line ==# a:last_line) "looping one section/song
                    let target = indexed_annotation.by_lines[a:first_line]
                    let song_stream = indexed_annotation.by_song_id[target.song_id].stream
                    let start_time = target.start_time
                    let next_line = a:first_line + 1
                    if has_key(indexed_annotation.by_lines, next_line) "checking if stop-time needs bounding
                        let next_target = indexed_annotation.by_lines[next_line]
                        if (next_target.song_id ==# target.song_id) "bounded by a subsequent section
                            let finish_time = next_target.start_time
                            call s:ExecuteSilently(tcb.build('clear'), a:debug_flag)
                            call s:ExecuteSilently(tcb.build('add ' . song_stream . ' :start-time=' . start_time . ' :stop-time=' . finish_time . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                            call s:ExecuteSilently(tcb.build('loop on'), a:debug_flag)
                            let state.loop = 1
                        else "different song next
                            call s:ExecuteSilently(tcb.build('clear'), a:debug_flag)
                            call s:ExecuteSilently(tcb.build('add ' . song_stream . ' :start-time=' . start_time . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                            call s:ExecuteSilently(tcb.build('loop on'), a:debug_flag)
                            let state.loop = 1
                        endif
                    else "last section/song in the playlist
                        call s:ExecuteSilently(tcb.build('clear'), a:debug_flag)
                        call s:ExecuteSilently(tcb.build('add ' . song_stream . ' :start-time=' . start_time . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                        call s:ExecuteSilently(tcb.build('loop on'), a:debug_flag)
                        let state.loop = 1
                    endif
                else "looping multiple sections/songs
                    let songs = []
                    let current_song = indexed_annotation.by_lines[a:first_line]
                    let current_start_time = current_song.start_time
                    for i in range(a:first_line + 1, a:last_line)
                        let target = indexed_annotation.by_lines[i]
                        if current_song.song_id !=# target.song_id
                            call add(songs, current_song)
                            let current_song = target
                        endif
                    endfor
                    call add(songs, current_song)
                    let song_stream_commands = [indexed_annotation.by_song_id[songs[0].song_id].stream . ' :start-time=' . songs[0].start_time]
                    for song in songs[1:]
                        call add(song_stream_commands, indexed_annotation.by_song_id[song.song_id].stream)
                    endfor
                    let next_line = a:last_line + 1
                    if has_key(indexed_annotation.by_lines, next_line) "checking if stop-time needs bounding
                        let next_target = indexed_annotation.by_lines[next_line]
                        if (next_target.song_id ==# target.song_id) "bounded by a subsequent section
                            let finish_time = next_target.start_time
                            let song_stream_commands[-1] = song_stream_commands[-1] . ' :stop-time=' . finish_time
                            call s:ExecuteSilently(tcb.build('clear'), a:debug_flag)
                            call s:ExecuteSilently(tcb.build('add ' . song_stream_commands[0] . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                            for stream_command in song_stream_commands[1:]
                                call s:ExecuteSilently(tcb.build('enqueue ' . stream_command . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                            endfor
                            call s:ExecuteSilently(tcb.build('loop on'), a:debug_flag)
                            let state.loop = 1
                        else "different song next
                            call s:ExecuteSilently(tcb.build('clear'), a:debug_flag)
                            call s:ExecuteSilently(tcb.build('add ' . song_stream_commands[0] . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                            for stream_command in song_stream_commands[1:]
                                call s:ExecuteSilently(tcb.build('enqueue ' . stream_command), a:debug_flag)
                            endfor
                            call s:ExecuteSilently(tcb.build('loop on'), a:debug_flag)
                            let state.loop = 1
                        endif
                    else "last section/song in the playlist
                        call s:ExecuteSilently(tcb.build('clear'), a:debug_flag)
                        call s:ExecuteSilently(tcb.build('add ' . song_stream_commands[0] . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                        for stream_command in song_stream_commands[1:]
                            call s:ExecuteSilently(tcb.build('enqueue ' . stream_command . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                        endfor
                        call s:ExecuteSilently(tcb.build('loop on'), a:debug_flag)
                        let state.loop = 1
                    endif
                endif
                let state.linewise_mode = 1
            endif
        else "regular play mode
            if a:first_line ==# a:last_line "play single song/section
                if has_key(indexed_annotation.by_lines, a:first_line)
                    "update latest line played
                    let state.line_selected = a:first_line
                    let target = indexed_annotation.by_lines[a:first_line]
                    let song_stream = indexed_annotation.by_song_id[target.song_id].stream
                    let start_time = target.start_time
                    call s:ExecuteSilently(tcb.build('clear'), a:debug_flag)
                    call s:ExecuteSilently(tcb.build('add ' . song_stream . ' ' . ':start-time=' . start_time . ' :rate=' . string(state.rate/10.0)), a:debug_flag)
                    if state.loop ==# 1
                        call s:ExecuteSilently(tcb.build('loop off'), a:debug_flag)
                        let state.loop = 0
                    endif
                    let state.linewise_mode = 0
                endif
            endif
        endif
        call s:ExecuteSilently(tcb.build('play'), a:debug_flag) "makes sure play status is properly set
        call s:renderInterface(indexed_annotation, self.getState())
    endfunction
    function internal.handleRateChange() closure
        "Waiting for this ticket to be resolved: https://trac.videolan.org/vlc/ticket/18375
        "For now, reload the playlist if either:
        "1. Playing normally, but on loop
        "2. Playing linewise, regardless of any subsequent loop toggle
        let linewise_mode = type(state.line_selected) ==# v:t_list
        if state.loop ==# 1 || linewise_mode
            if linewise_mode
                call self.interpretLinesToPlay(state.line_selected[0], state.line_selected[1], 1)
            else
                call self.interpretLinesToPlay(state.line_selected, state.line_selected, 0)
            endif
        else
            call s:ExecuteSilently(tcb.build('rate ' . string(state.rate/10.0)), a:debug_flag)
        endif
        call s:renderInterface(indexed_annotation, self.getState())
    endfunction

    "interface
    let drill = {}
    function drill.loadAnnotation(annotation_path) closure abort
        let annotation_spec = json_decode(join(readfile(a:annotation_path)))
        let indexed_annotation = s:indexAnnotation(annotation_spec)
        if s:isTelnetServerStarted(a:telnet_port) ==# 0
            call s:startTelnetServer(g:vlcdrill#bin#path, a:telnet_port, a:telnet_password, a:log_location)
        else
            call s:ExecuteSilently(tcb.build('clear'), a:debug_flag)
            call s:ExecuteSilently(tcb.build('loop off'), a:debug_flag)
            call s:ExecuteSilently(tcb.build('rate 1'), a:debug_flag)
        endif
        let annotation_loaded = 1
    endfunction
    function drill.hasLoadedAnnotation() closure
        return annotation_loaded
    endfunction
    function drill.interpretLinesToPlay(first_line, last_line, currently_visual) closure
        call internal.interpretLinesToPlay(a:first_line, a:last_line, a:currently_visual)
    endfunction
    function drill.pause() closure
        call s:ExecuteSilently(tcb.build('pause'), a:debug_flag)
        call s:renderInterface(indexed_annotation, internal.getState())
    endfunction
    function drill.toggleLoop() closure
        if state.loop ==# 0
            let state.loop = 1
            let command = 'on'
        else
            let state.loop = 0
            let command = ' off'
        endif
        call s:ExecuteSilently(tcb.build('loop ' . command), a:debug_flag)
        call s:renderInterface(indexed_annotation, internal.getState())
    endfunction
    function drill.volumeUp() closure
        call s:ExecuteSilently(tcb.build('volup'), a:debug_flag)
        call s:renderInterface(indexed_annotation, internal.getState())
    endfunction
    function drill.volumeDown() closure
        call s:ExecuteSilently(tcb.build('voldown'), a:debug_flag)
        call s:renderInterface(indexed_annotation, internal.getState())
    endfunction
    function drill.debug() closure
        return {
                    \'indexed': indexed_annotation,
                    \'state': state
                    \}
    endfunction
    function drill.renderInterface() closure
        call s:renderInterface(indexed_annotation, internal.getState())
    endfunction
    function drill.rateIncrease() closure
        let state.rate = state.rate + 1
        call internal.handleRateChange()
    endfunction
    function drill.rateDecrease() closure
        let state.rate = state.rate - 1
        call internal.handleRateChange()
    endfunction
    function drill.rateNormal() closure
        let state.rate = 10
        call internal.handleRateChange()
    endfunction
    function drill.getCurrentTime() closure
        let current_time = s:matchRawRc(system(tcb.build('get_time')))
        let total_time = s:matchRawRc(system(tcb.build('get_length')))
        let state.current_time = [current_time, total_time]
        call s:renderInterface(indexed_annotation, internal.getState())
    endfunction
    function drill.cleanup() closure
        call s:ExecuteSilently(tcb.build('shutdown'), a:debug_flag)
        silent execute "!rm " . a:log_location
    endfunction
    function drill.prev() closure
        call s:ExecuteSilently(tcb.build('prev'), a:debug_flag)
        call s:renderInterface(indexed_annotation, internal.getState())
    endfunction
    function drill.next() closure
        call s:ExecuteSilently(tcb.build('next'), a:debug_flag)
        call s:renderInterface(indexed_annotation, internal.getState())
    endfunction
    return drill
endfunction

function! s:openInterface() abort
    let existing_drill_buffer = bufnr(s:DRILL_BUF_NAME)

    if existing_drill_buffer ==# -1 "buffer doesn't exist; make one
        execute "vnew " . s:DRILL_BUF_NAME
    else "buffer already exists; give it a window/viewport
        let existing_drill_window = bufwinnr(existing_drill_buffer)
        if existing_drill_window == -1 "window doesn't exist; make one
            "splits the window with the current buffer and the one specified
            execute "vsplit +buffer" . existing_drill_buffer
        else "window exists; focus on it
            if winnr() != existing_drill_window
                execute existing_drill_window . "wincmd w"
            endif
        endif
    endif
endfunction

let s:drill = s:DrillInterface(s:TELNET_PORT, s:TELNET_PASSWORD, s:LOG_LOCATION, s:DEBUG_FLAG)

"range argument stops this being called multiple times
function! s:VlcDrillPlay() abort range
    call s:drill.interpretLinesToPlay(a:firstline, a:lastline, 0)
endfunction

function! s:VlcDrillPlayFromLinewise() abort range
    call s:drill.interpretLinesToPlay(a:firstline, a:lastline, 1)
endfunction

function! s:VlcDrillTogglePause() abort
    call s:drill.pause()
endfunction

function! s:VlcDrillToggleLoop() abort
    call s:drill.toggleLoop()
endfunction

function! s:VlcDrillDebug() abort
    echo s:drill.debug()
endfunction

function! s:showInterface() abort
    call s:drill.renderInterface()
endfunction

function! s:VlcDrillClose() abort
    quit
endfunction

function! s:VlcDrillPrev() abort
    call s:drill.prev()
endfunction

function! s:VlcDrillNext() abort
    call s:drill.next()
endfunction

function! s:VlcDrillVolUp() abort
    call s:drill.volumeUp()
endfunction

function! s:VlcDrillVolDown() abort
    call s:drill.volumeDown()
endfunction

function! s:VlcDrillRateIncrease() abort
    call s:drill.rateIncrease()
endfunction

function! s:VlcDrillRateDecrease() abort
    call s:drill.rateDecrease()
endfunction

function! s:VlcDrillRateNormal() abort
    call s:drill.rateNormal()
endfunction

function! s:VlcDrillGetCurrentTime() abort
    call s:drill.getCurrentTime()
endfunction

augroup DrillAug
    autocmd!
    "TODO how to pass in dynamic buffer name?
    autocmd BufNewFile __VlcDrill__ call s:setDrillBufferSettings()
    "wildcard so that cleanup is called even if interface buffer is not in focus
    autocmd VimLeavePre * call s:drill.cleanup()
augroup END

function! s:VlcDrillHandleAnnotation() abort
    while !exists("g:vlcdrill#annotation#path") || empty(expand(g:vlcdrill#annotation#path))
        let g:vlcdrill#annotation#path = input("Annotation JSON not found. Enter path for annotation JSON: ", "", "file")
    endwhile
endfunction

function! s:VlcConfigured(vlc_bin) abort
    let pushed_shellcmdflags = &shellcmdflag
    set shellcmdflag=-ic
    call system(a:vlc_bin . ' --version')
    "https://stackoverflow.com/a/9828589/1010076
    let exit_code = v:shell_error
    let &shellcmdflag=pushed_shellcmdflags
    if exit_code ==# 0
        return 1
    else
        return 0
    endif
endfunction

function! vlcdrill#VlcDrillShow() abort
    while !s:VlcConfigured(g:vlcdrill#bin#path)
        let g:vlcdrill#bin#path = input("VLC executable not correctly configured. Enter bin path or alias: ", "", "file")
    endwhile
    call s:VlcDrillHandleAnnotation()
    if !s:drill.hasLoadedAnnotation()
        call s:drill.loadAnnotation(expand(g:vlcdrill#annotation#path))
    endif
    call s:drill.renderInterface()
endfunction

function! vlcdrill#VlcDrillLoadAnnotation() abort
    let annotation_path = input("Enter path for annotation JSON (leave empty to reload current annotation): ", "", "file")
    if strlen(annotation_path) ==# 0
        call s:drill.loadAnnotation(expand(g:vlcdrill#annotation#path))
    else
        let g:vlcdrill#annotation#path = annotation_path
        call s:VlcDrillHandleAnnotation()
        call s:drill.loadAnnotation(expand(g:vlcdrill#annotation#path))
    endif
    call s:drill.renderInterface()
endfunction
