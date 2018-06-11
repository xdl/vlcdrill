# VLC Drill

Vim interface for controlling VLC over telnet using the `rc` interface. (Wrote a bit more on the motivation behind the plugin [here](https://xiaodi.li/projects/vlcdrill))

![Preview](assets/preview.gif)

## Installation

### Pathogen

    cd ~/.vim/bundle
    git clone git://github.com/xdl/vlcdrill.git

And then `:call pathogen#helptags()` to generate the helptags.

## Annotation Format

This is a valid annotation file:

```javascript
{
  "playlist": [{
    "title": "Stupid Thing",
    "stream": "https://www.youtube.com/watch?v=sTm7aZE6u6w",
    "sections": [
      [16, "verse 1"],
      [43, "chorus 2"],
      [65, "verse 2"],
      [93, "chorus 2"],
      117,
      145,
      172,
      199
    ]
  }, {
    "title": "Stupid Thing",
    "stream": "https://www.youtube.com/watch?v=sTm7aZE6u6w",
  }, {
    "stream": "https://www.youtube.com/watch?v=sTm7aZE6u6w"
  },
    "https://www.youtube.com/watch?v=sTm7aZE6u6w"
  ]
}
```

The format is generally:

```javascript
  {
    "playlist": [
      <Stream>...
    ]
  }
```

Where `<Stream>` can be:

* `stream <string>` containing the path for the local file or stream location of the song
* `{stream <string>, title <string>?, section <Section>?}` 

Where `<Section>` can be:

* `start_time <int>`, containing the start time of the section
* `[start_time <int>, description <string>]`

See the `example_annotations/` directory for more examples (The `aimee_mann_youtube.json` is loaded by default, if one isn't set in `g:vlcdrill#annotation#path`).

## Bindings

* `<Up>`: volume up
* `<Down>`: volume down
* `<Space>`: toggle play/pause
* `<Left>`: previous VLC playlist item in selection
* `<Right>`: next VLC playlist item in selection
* `p` (normal mode): play section under cursor till end of its stream
* `p` (linewise visual mode): play and loop highlighted section(s)
* `ri`: increase rate
* `rd`: decrease rate
* `rn`: normal rate
* `u`: show seconds played of stream
* `o`: toggle loop
* `q`: close VlcDrill buffer

## Customisation

Bindings and vlc/annotation paths can be customised in your `vimrc`:

    let g:vlcdrill#bin#path = '/Applications/VLC.app/Contents/MacOS/VLC' "defaults to 'vlc'
    let g:vlcdrill#annotation#path = '/path/to/your/annotation.json' # defaults to '/../example_annotations/aimee_mann_youtube.json'
    let g:vlcdrill#resolveWithYoutubeDl = 0 # defaults to 1
    nnoremap <leader>vds :VlcDrillShow<CR>
    nnoremap <leader>vdl :VlcDrillLoadAnnotation<CR>

## Compatibility

Have tested it on MacOS (El Capitan → High Sierra), Ubuntu (14.04, 16.04) with VLC 3.0.3. Should work on most unix-y systems with the following commands available:

* `echo`
* `lsof`
* `nc`
* `youtube-dl` (optional)

Vim 8 is needed for some of the newer functions (e.g. `closure` and `json_decode`).

## Known Issues

Some YouTube links don't seem to be recognised on the some of the earlier versions of VLC - try updating VLC if that's the case.
