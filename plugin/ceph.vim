" Vim plugin for ceph development
" Description:  A vim plugin for Ceph
" Maintainer:   Imran Imtiaz <imran.imtiaz@uk.ibm.com
" Plugin URL:   https://github.com/imran-imtiaz/vim-ceph
"

if exists('g:loaded_ceph')
    finish
endif

let g:loaded_ceph = 1

if v:version < 700
    call s:warning("ceph: Vim version is too old, vim-ceph requires at least 7.0")
    finish
endif

function! s:init_var(var, value) abort
    if !exists('g:ceph_' . a:var)
        execute 'let g:ceph_' . a:var . '=' . string(a:value)
    endif
endfunction

function! s:setup_options() abort
    let options = [
                \ ['remote_server',  ''],
                \ ['remote_workdir', '/'],
                \ ['local_workdir',  ''],
                \ ['checkout_dir',   'ceph'],
                \ ['github_server',  'git@github.com'],
                \ ['github_repo',    'ceph/ceph.git'],
                \ ['github_branch',  'main'],
                \ ['ssh_cmd',        'ssh -oNumberOfPasswordPrompts=0 -oStrictHostKeyChecking=no '],
                \ ]
    for [opt, val] in options
        call s:init_var(opt, val)
    endfor
endfunction
call s:setup_options()

function! s:sanitize_slashes(dir1, dir2)
    return string(trim(a:dir1, '/', 2) . '/' . trim(a:dir2, '/', 2))
endfunction

if !exists('g:ceph_remote_workspace')
    execute 'let g:ceph_remote_workspace=' . s:sanitize_slashes(g:ceph_remote_workdir, g:ceph_checkout_dir)
endif

if !exists('g:ceph_local_workspace')
    let workdir =  g:ceph_local_workdir ==# "." ? getcwd() : g:ceph_local_workdir
    execute 'let g:ceph_local_workspace=' . s:sanitize_slashes(workdir, g:ceph_checkout_dir)
endif

" TODO
function! s:setup_keymaps() abort
    let keymaps = [
                \ ['init',          'i'],
                \ ['initlocal',  ['il']],
                \ ['initremote', ['ir']],
                \ ['install',       'r'],
                \ ['vstart',        'v'],
    ]
    for [map, key] in keymaps
        call s:init_var('map_' . map, key)
        unlet key
    endfor
endfunction

augroup ceph
    au BufRead,BufEnter,BufNewFile *.c,*.h
                \ hi cephPlfb ctermfg=33 |
                \ hi cephEm ctermfg=226 |
                \ hi cephPl ctermfg=186 |
                \ hi cephList ctermfg=105 |
                \ hi cephDv ctermfg=134 |
                \ hi cephTrace ctermfg=142 |
                \ hi cephPlmu ctermfg=224 |
                \ hi cephAssert ctermfg=9 |
                \ hi cephPlio ctermfg=113 |
                \ hi cephPlid ctermfg=77 |
                \ hi cephPltm ctermfg=199 |
                \ hi cephStruct ctermfg=208 |
                \ syn keyword cType uchar int8 uint8 int16 uint16 int32 uint32 int64 uint64 intptr uintptr u8 u16 u32 u64 bool bool8 Ss_iobref Plio_pb Plio_clb |
                \ syn match cType /\vSs_dlist\w*/ |
                \ syn match cephDv /\v<dv_\w+>/ |
                \ syn match cephPl /\v<pl_\w+>/ |
                \ syn match cephTrace /\v<pl_trace_\w+>/ |
                \ syn match cephPlfb /\v<plfb_\w+>/ |
                \ syn match cephPlid /\v<plid_\w+>/ |
                \ syn match cephEm /\v<Em_\w+>/ |
                \ syn match cephAssert /\v<(ss_panic|ss_assert)\w*>/ |
                \ syn match cephList /\v<s{2,3}d?list_\w+>/ |
                \ syn match cephPlmu /\v<plmu_\w+>/ |
                \ syn match cephPlio /\v<plio_\w+>/ |
                \ syn match cephStruct /\v<SS_[A-Z_]+>/ |
                \ syn match cephPltm /\v<pltm_\w+>/ |
                \ syn keyword Boolean FALSE TRUE
augroup end

command! -nargs=0 CephInit          call ceph#init()
command! -nargs=0 CephInitLocal     call ceph#init_local()
command! -nargs=0 CephInitRemote    call ceph#init_remote()
command! -nargs=0 CephBuild         call ceph#build()
command! -nargs=0 CephVstart        call ceph#vstart()
command! -nargs=0 CephCleanRemote   call ceph#clean_remote()
