if !exists("g:vlcdrill#bin#path")
    let g:vlcdrill#bin#path = 'vlc'
endif

"Symbols/Constants
let s:DRILL_BUF_NAME = "__VlcDrill__"
let s:TELNET_PORT = 4212
let s:TELNET_PASSWORD = "test"
let s:LOG_LOCATION = "$HOME/.vlc_drill.log"
"set to 1 to send telnet commands to :messages as well
let s:DEBUG_FLAG = 0

function! s:DrillInterface(telnet_port, telnet_password, log_location, debug_flag) abort

    let annotation_loaded = 0

    "interface
    let drill = {}
    function drill.loadAnnotation(annotation_path) dict closure
        echom 'loading ' . a:annotation_path
        let annotation_loaded = 1
    endfunction
    function drill.hasLoadedAnnotation() dict closure
        return annotation_loaded
    endfunction
    function drill.renderInterface() dict closure
        echom "rendering interface"
    endfunction
    return drill
endfunction

let s:drill = s:DrillInterface(s:TELNET_PORT, s:TELNET_PASSWORD, s:LOG_LOCATION, s:DEBUG_FLAG)

function! s:VlcDrillHandleAnnotation() abort
    while !exists("g:vlcdrill#annotation#path") || empty(glob(g:vlcdrill#annotation#path))
        let g:vlcdrill#annotation#path = input("Annotation JSON not found. Enter path for annotation JSON: ", "", "file")
    endwhile
endfunction

function! s:VlcConfigured(vlc_bin) abort
    let pushed_shellcmdflags = &shellcmdflag
    set shellcmdflag=-ic
    echom a:vlc_bin
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
        call s:drill.loadAnnotation(g:vlcdrill#annotation#path)
    endif
    call s:drill.renderInterface()
endfunction

function! vlcdrill#VlcDrillLoadAnnotation() abort
    let g:vlcdrill#annotation#path = input("Enter path for annotation JSON: ", "", "file")
    call s:VlcDrillHandleAnnotation()
    call s:drill.loadAnnotation(g:vlcdrill#annotation#path)
    call s:drill.renderInterface()
endfunction
