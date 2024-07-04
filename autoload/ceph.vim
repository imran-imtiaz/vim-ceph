let s:save_cpo = &cpo
set cpo&vim
let s:commit_hash = 0
let s:compile_commands = g:ceph_local_workspace . '/build/compile_commands.json'
let s:compile_commands_orig = s:compile_commands . '.orig'

function! ceph#run_local(cmd, ...) abort
    let use_dispatch = a:0 > 0 ? a:1 : 0
    if exists(":Dispatch") && use_dispatch == 1
        let save_make = &makeprg
        let &makeprg = a:cmd
        Dispatch
        let &makeprg = save_make
        return
    elseif exists(":Make") && use_dispatch == 2
        let save_make = &makeprg
        let &makeprg = a:cmd
        Make
        let &makeprg = save_make
        return
    elseif has('python3') || has('python2')
        if has('python3')
            let pyx = 'py3 '
            let python_eval = 'py3eval'
        elseif has('python2')
            let pyx = 'py2 '
            let python_eval = 'pyeval'
        endif
        let l:pc = 0
        exec pyx . 'import subprocess, vim'
        exec pyx . '__argv = {"args":vim.eval("a:cmd"), "shell":True}'
        exec pyx . '__argv["stdout"] = subprocess.PIPE'
        exec pyx . '__argv["stderr"] = subprocess.STDOUT'
        exec pyx . '__pp = subprocess.Popen(**__argv)'
        exec pyx . '__return_text = __pp.stdout.read()'
        exec pyx . '__pp.stdout.close()'
        exec pyx . '__return_code = __pp.wait()'
        exec 'let l:hr = '. python_eval .'("__return_text")'
        exec 'let l:pc = '. python_eval .'("__return_code")'
        let s:shell_error = l:pc
        return l:hr
    else
        let hr = system(a:cmd)
        let s:shell_error = v:shell_error
        return hr
    endif
endfunction

function! ceph#run_local_retry(cmd, attempts)
    for i in range(a:attempts)
        call ceph#run_local(a:cmd)
        if s:shell_error == 0
            break
        endif
    endfor
endfunction

function! ceph#run_remote(cmd)
    call ceph#run_local(g:ceph_ssh_cmd . g:ceph_remote_server . ' ' . shellescape(a:cmd))
endfunction

function! ceph#dispatch_local(cmd)
    call ceph#run_local(a:cmd, 1)
endfunction

function! ceph#make_local(cmd)
    call ceph#run_local(a:cmd, 2)
endfunction

function! ceph#dispatch_remote(cmd)
    call ceph#run_local(g:ceph_ssh_cmd . g:ceph_remote_server . ' ' . shellescape(a:cmd), 1)
endfunction

function! ceph#warning(msg) abort
    echohl WarningMsg
    echomsg a:msg
    echohl None
endfunction

function! ceph#error(msg) abort
    echohl WarningMsg
    echomsg a:msg
    echohl None
    finish
endfunction

function! ceph#repo_exists(dir, silent, ...)
    let Run_fn = a:0 ? function('ceph#run_remote') : function('ceph#run_local')
    let repo = a:dir . '/.git'

    call Run_fn('ls -ld '. repo)
    if s:shell_error == 0
        if !a:silent
            call ceph#warning('Looks like ' . a:dir . ' already has a repo, unable to proceed!')
        endif
        return 1
    endif
    return 0
endfunction

function! ceph#passwordless_setup_exists()
    call ceph#run_local_retry('echo | ssh -T -oPasswordAuthentication=no  -oBatchMode=yes ' .
                \ g:ceph_github_server . ' 2>&1 | grep "successfully authenticated"', 3)
    if s:shell_error != 0
        call ceph#warning('Looks like passwordless ssh to ' .
                    \ g:ceph_github_server . ' has not been setup on local machine')
        return 0
    endif
    call ceph#run_local_retry('echo | ssh -oPasswordAuthentication=no  -oBatchMode=yes ' .
                \ g:ceph_remote_server . ' exit', 3)
    if s:shell_error != 0
        call ceph#warning('Looks like passwordless ssh to ' .
                    \ g:ceph_remote_server . ' has not been setup on local machine')
        return 0
    endif
    return 1
endfunction

function! ceph#git_remote_exists(remote)
    call ceph#run_local('cd ' . g:ceph_local_workspace . ' && git remote | grep ' . a:remote)
    if s:shell_error != 0
        call ceph#warning('No git remote present, please initialise the repo first')
        return 0
    endif
    return 1
endfunction

function! ceph#init() abort
    if !ceph#repo_exists(g:ceph_local_workspace, v:false) && ceph#passwordless_setup_exists()
        echo "Initialise a new workspace in " . g:ceph_local_workspace . " (y/n)"
        let confirm = nr2char(getchar())
        if confirm ==? 'y'
            call ceph#dispatch_local(ceph#get_init_command("full"))
        endif
    endif
endfunction

function! ceph#init_remote() abort
    if !ceph#repo_exists(g:ceph_local_workspace, v:true) && ceph#passwordless_setup_exists()
        call ceph#error('No local workspace found, first run local set up')
        finish
    endif
    if !ceph#repo_exists(g:ceph_remote_workspace, v:false, "remote")
        call ceph#dispatch_local(ceph#get_init_command("remote"))
    endif
endfunction

function! ceph#init_local() abort
    if !ceph#repo_exists(g:ceph_local_workspace, v:false) && ceph#passwordless_setup_exists()
        call ceph#dispatch_local(ceph#get_init_command("local"))
    endif
endfunction

function! ceph#clean_remote() abort
    if ceph#git_remote_exists(g:ceph_remote_server)
        call ceph#dispatch_remote(ceph#get_clean_remote_command())
    endif
endfunction

function! ceph#test()
    echo ceph#get_file_chksum(s:compile_commands)
endfunction

function! ceph#build() abort
    if ceph#git_remote_exists(g:ceph_remote_server)
        call ceph#update_compile_commands()
        " commit and update the hash
        call ceph#commit()
        let cmd = 'cd ' . g:ceph_local_workspace . ' && ' .
                    \ 'git push --no-verify -v -f ' . g:ceph_remote_server . ' ' . s:commit_hash . ':refs/heads/build && '.
                    \ g:ceph_ssh_cmd . g:ceph_remote_server . ' ' . shellescape(ceph#get_remote_build_command()) . ' && ' .
                    \ ceph#get_rsync_command()
        call ceph#make_local(cmd)
    endif
endfunction

function! ceph#vstart() abort
    echo "Run vstart.sh in containter? (y/n): "
    let confirm = nr2char(getchar())
    if confirm ==? 'y'
        call ceph#dispatch_remote(ceph#get_vstart_command())
    endif
endfunction

function! ceph#stop() abort
    echo "Run stop.sh in containter? (y/n): "
    let confirm = nr2char(getchar())
    if confirm ==? 'y'
        call ceph#dispatch_remote(ceph#get_stop_command())
    endif
endfunction

function! ceph#get_init_command(target)
    let cmd =  ''
    if a:target ==# "local" || a:target ==# "full"
        let cmd .= 'cd '. g:ceph_local_workdir . ' && ' .
                    \'git config --global push.default current && ' .
                    \ 'git config --global pull.rebase true && ' .
                    \ 'git config --global http.sslVerify true && ' .
                    \ 'git config --global credential.helper store && ' .
                    \ 'git config --global branch.autosetuprebase always && ' .
                    \ 'git config --global core.autocrlf input && ' .
                    \ 'git config --global lfs.allowincompletepush true && ' .
                    \ 'git clone ' . g:ceph_github_server . ':' . g:ceph_github_repo . ' -b ' .  g:ceph_github_branch . ' ' . g:ceph_checkout_dir . ' && ' .
                    \ 'cd ' . g:ceph_checkout_dir  . ' && ' .
                    \ 'git remote add ' . g:ceph_remote_server . ' ssh://' . g:ceph_remote_server . ':' . g:ceph_remote_workspace
        let cmd .= a:target ==# "full" ? ' && ' : ''
    endif
    if a:target ==# "remote" || a:target ==# "full"
        let cmd .= 'cd '. g:ceph_local_workspace . ' && ' .
                    \ g:ceph_ssh_cmd . g:ceph_remote_server . ' ' . shellescape(ceph#get_remote_git_init_command()) . ' && ' .
                    \ 'git push --no-verify -v -f ' . g:ceph_remote_server
    else
        call ceph#warning("Invalid target")
    endif
    return cmd
endfunction

function! ceph#commit() abort
    let save_cwd = getcwd()
    execute "cd " . g:ceph_local_workspace
    let out = trim(ceph#run_local('git log -1 --pretty=%s'))
    if out ==# "build commit"
        call ceph#run_local('git commit -a --amend -C HEAD --allow-empty')
    else
        let out = ceph#run_local('git commit -a -m "build commit" --allow-empty')
    endif
    if s:shell_error != 0
        throw "Commit failed"
    else
        let s:commit_hash = trim(ceph#run_local('git log -1 --pretty=%H'))
        call ceph#run_local('git reset --soft HEAD^')
    endif
    execute "cd " . save_cwd
endfunction

function! ceph#get_remote_build_command()
    return 'cd ' . g:ceph_remote_workspace . ' && ' .
                \ 'git checkout ' . s:commit_hash . ' && ' .
                \ 'CMAKE_EXPORT_COMPILE_COMMANDS=ON ./do_cmake.sh || true' . ' && ' .
                \ 'cd build' . ' && ' .
                \ 'ninja -l40 -j20'
endfunction

function! ceph#get_clean_remote_command()
    return 'cd ' . g:ceph_remote_workspace . ' && ' .
                \ 'git clean -qfdx && ' .
                \ 'git reset --hard HEAD && ' .
                \ 'git fetch && ' .
                \ 'git reset --hard ' . g:ceph_github_branch
endfunction

function! ceph#get_vstart_command()
    return 'cd ' . g:ceph_remote_workspace . '/build' . ' && ' .
                \ 'MDS=0 MON=1 OSD=1 MGR=1 ../src/vstart.sh ' .
                \ '--debug --new -x --localhost ' . 
                \ '-o timeout=10000 -o session_timeout=10000'
endfunction

function! ceph#get_stop_command()
    return 'cd ' . g:ceph_remote_workspace . '/build' . ' && ' .
                \ '../src/stop.sh'
endfunction

function! ceph#get_remote_git_init_command()
    return 'mkdir -p ' . g:ceph_remote_workspace . ' && ' .
                \ 'cd ' . g:ceph_remote_workspace . ' && ' .
                \ 'git init'
endfunction

function! ceph#get_rsync_command()
    let filter_pattern = "--include '*/' " .
                \ "--include '*.h' " .
                \ "--include '*.hpp' " .
                \ "--include '*.c' " .
                \ "--include '*.cc' " .
                \ "--include '*.json' " .
                \ "--exclude '*' "
    return 'rsync -v --copy-links -aK -e "ssh -T" ' . filter_pattern .
                \ g:ceph_remote_server . ':' . g:ceph_remote_workspace . '/build ' . g:ceph_local_workspace . ' && ' .
                \ $"mv -f {s:compile_commands} {s:compile_commands_orig}" . ' && ' .
                \ $"ln -sf {s:compile_commands}.updated {s:compile_commands}"
endfunction

function! ceph#update_compile_commands()
    if filereadable(s:compile_commands_orig)
        call ceph#run_local(ceph#get_compile_commands_awk_command())
    endif
endfunction

function! ceph#get_compile_commands_awk_command()
    let awk_begin =<< trim eval END
    lws = "{g:ceph_local_workspace}"
    rws = "{g:ceph_remote_workspace}"
    gcc = "\"{trim(system('which gcc'))}"
    cpp = "\"{trim(system('which g++'))}"
    END
    let awk_cmd =<< trim END
awk '
    BEGIN {
    %s
    }

    $1 ~ /directory/ {
        gsub(rws, lws)
    }

    $1 ~ /command/ {
        sub("-D__linux__ ", "")
        sub("-D__CEPH__", "")
        gsub(rws, lws)
        if ($2 ~ /gcc/) $2 = gcc
        if ($2 ~ /g\+\+/) $2 = cpp
    }

    $1 ~ /file/ {
        gsub(rws, lws)
    }

    { print $0 }
' %s
    END
    let pipeline =<< trim eval END
    {s:compile_commands_orig} > {s:compile_commands}.updated;
    ln -sf {s:compile_commands}.updated {s:compile_commands}
    END

    return printf(join(awk_cmd, "\n"), join(awk_begin, "\n"), join(pipeline))
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
