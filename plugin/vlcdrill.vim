if exists('g:loaded_vlcdrill') || &compatible
    finish
endif
let g:loaded_vlcdrill = 1

command! -nargs=0 VlcDrillShow call vlcdrill#VlcDrillShow()
command! -nargs=0 VlcDrillLoadAnnotation call vlcdrill#VlcDrillLoadAnnotation()
