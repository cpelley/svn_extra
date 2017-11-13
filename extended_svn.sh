#The MIT License (MIT)
#
#Copyright (c) 2016 - 2017 Carwyn Pelley
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

# The following script provides git-like functionality in svn
# Simply source this file in your .bashrc or equivelent file.

# Functionality includes:
# svn stash (git stash)
# svn clean (git clean)
# svn rebase (git rebase)
# svn browse


_unknown_args() {
    echo 'svn-e: Unrecognised command' '"'$@'"' 1>&2
    return 1
}


_svn_base_revision() {
    svn log -r 1:HEAD --limit 1 --stop-on-copy --xml | grep -oP '.*revision="\K[0-9]*';
}


_svn_uncommitted_changes() {
    svn status --ignore-externals | grep -ve '^?' -ve '^X';
}


_svn_get_current_branch() {
    svn info --xml | grep -oP "(\<relative-url\>)\K[^<]*";
}


svn_rebase() {
    case $* in
        --help|-h)
            echo 'info: Rebase against the specified SVN_URL.  Currently a single squashed commit is performed.'
            echo 'usage: svn rebase SVN_URL... '
        return ;;
    esac

    # Ensure attempting to rebase a working copy
    svn info 1> /dev/null

    if [[ $(_svn_uncommitted_changes) ]]; then
        echo 'svn-e: cannot complete rebase, first commit uncommited changes' 1>&2;
        return 1;
    fi

    case $* in
        --continue)
            if [[ -z ${SVN_REBASE_BRANCH} ]]; then
                echo 'svn-e: Unable to deduce rebase status' 1>&2;
                return 1;
            fi
            if [[ ${SVN_REBASE_BRANCH} != $(_svn_get_current_branch) ]]; then
                echo 'svn-e: Unable to continue rebase: ' $(_svn_get_current_branch) ' != ' ${SVN_REBASE_BRANCH} 1>&2;
                return 1;
            fi
                
            svn rm -q --non-interactive ${SVN_BRANCH} -m "REBASE: Original branch deleted" &&
            svn mv -q --non-interactive ${SVN_REBASE_BRANCH} ${SVN_BRANCH} -m "REBASE: Renaming rebase branch name" &&
            svn switch -q --non-interactive ${SVN_BRANCH} &&
            unset SVN_BRANCH; unset SVN_BRANCH_PATH; unset SVN_REBASE_BRANCH;
            echo 'Rebase complete' ;;
        *)
            if [[ ! $1 ]]; then
                echo 'svn-e: Please specify URL which you want to rebase against.

    svn rebase <SVN_URL>' 1>&2;
                return 1;
            fi
            export SVN_BRANCH=$(svn info --xml | grep -oP "(\<relative-url\>)\K[^<]*") &&
            export SVN_BRANCH_PATH=$(dirname ${SVN_BRANCH}) &&
            export SVN_REBASE_BRANCH=${SVN_BRANCH}-rebase &&
            echo Attempting to rebase: $SVN_BRANCH against $1 &&
            svn cp $1 ${SVN_REBASE_BRANCH} -m "REBASE: Rebase branch created" &&
            svn switch ${SVN_REBASE_BRANCH} && svn revert -qR . &&
            svn merge ${SVN_BRANCH} . &&
            echo 'Commit changes, then type "svn rebase --continue"' ;;
    esac
}


svn_clean() {
    clean_files() {
         svn status --no-ignore | grep -e ^\? -e ^I | awk '{print $2}';
    }
    case $* in
        --help|-h)
            echo 'info: Clean repository by removing all files with "?" and "I" status.'
        echo '      "svn clean -dry-run|-n" for a dry-run.'
        echo 'usage: svn clean' ;;
    --dry-run|-n)
        clean_files ;;
        "")
            clean_files | xargs -r rm -r ;;
        *)
            _unknown_args "$@" ;;
    esac
}


svn_stash() {
    case $* in
        --help|-h)
            echo 'info: Stash changes.'
        echo '      "svn stash apply" re-applies these changes.'
            echo 'usage: svn stash'
        return ;;
    esac

    # Ensure attempting to rebase a working copy
    svn info 1> /dev/null &&

    case $* in
        apply)
            # Apply patch and remove patch file if successful
            svn patch patch_name.patch ;;

        "")
            if [[ ! $(_svn_uncommitted_changes) ]]; then
                echo 'svn-e: no uncommited changes to stash' 1>&2;
                return 1;
            fi
            # Patch svn diff - remove added files - svn revert
            svn diff --internal-diff > patch_name.patch &&
            svn status | grep -e ^A | awk '{print $2}' | xargs rm -rf 2> /dev/null; svn revert -R . &&
            echo 'Type "svn stash apply" to apply the patch.' ;;
        *)
            _unknown_args "$@" ;;
    esac
}


svn_browse_trac() {
    trac_url() {
        # Generate string and replace svn with trac.
        _tmp_var1=$(svn info | grep ^URL | awk '{print $2}' | sed 's/svn/trac/g')
        # Find directory name after 'trac'.
        _tmp_sting_match=$(echo ${_tmp_var1} | grep -oP "(trac/)\K(.[^/]*)")
        # Inject 'browser' at this location.
        echo $_tmp_var1 | sed "s/${_tmp_sting_match}/${_tmp_sting_match}\/browser/g"
    }

    case $* in
        --help|-h)
            echo 'info: Open current URL using the trac project management.'
            echo 'usage: svn browse' ;;
        -u)
            shift
            echo $(trac_url) ;;
        "")
            xdg-open $(trac_url) ;;
        *)
            _unknown_args "$@" ;;
    esac
}


bdiff() {
    case $* in
        --help|-h)
            echo 'info: Perform a diff against the base revision of the branch.'
            echo 'usage: svn bdiff' ;;
        *)
            svn diff -r $(_svn_base_revision) $@ ;;
    esac
}


svn() {
    case $* in
        "rebase "*|rebase)
            shift && svn_rebase "$@" ;;
        "clean "*|clean)
            shift && svn_clean "$@" ;;
        "stash "*|stash)
            shift && svn_stash "$@" ;;
        "bdiff "*|bdiff)
            shift && bdiff "$@" ;;
        "browse "*|browse)
            shift && svn_browse_trac "$@" ;;
        help|--help|-h)
                command svn "$@"
            echo; echo "svn extended usage:"
            echo "   rebase";
            echo "   clean";
            echo "   stash";
            echo "   bdiff";
            echo "   browse";
            echo "see: https://gist.github.com/cpelley/5aab41aff4d8a2ec5161"
            ;;
        *)
            command svn "$@" ;;
    esac
}
