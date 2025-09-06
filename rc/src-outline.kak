# src-outline: A simple wrapper of Universal Ctags.

# The plugin doesn't and won't provide any language specific feature.
# It is intended to only process the output of ctags as general as possible.

hook global KakBegin .* %sh{
    if ! command -v ctags > /dev/null 2>&1 || ! command -v readtags > /dev/null 2>&1; then
        echo "echo -debug ctags and readtags are needed for src-outline command"
        exit
    fi
    echo "require-module src-outline"
}

provide-module src-outline %{

declare-option -docstring "name of the client in which utilities display information" \
    str toolsclient
declare-option -docstring "name of the client in which all source code jumps will be executed" \
    str jumpclient

add-highlighter shared/src-outline group
add-highlighter shared/src-outline/group regex '^ *(\S+)$' 1:keyword
add-highlighter shared/src-outline/tags regex '^ +([^\t\n]+)\t(typename:[^\t\n]+\t)?([^\t\n]+\t)?(#\d+)$' 1:variable 2:value 3:type 4:comment

hook -group src-outline-syntax global WinSetOption filetype=src-outline %{
    add-highlighter window/src-outline ref src-outline
    hook -always -once window WinSetOption filetype=.* %{
        remove-highlighter window/src-outline
    }
}

define-command -docstring '
src-outline: Show the outline of the source file.
Press <ret> to jump to the line.' \
    -params 0..1 src-outline %{ evaluate-commands %sh{
    buffile="${1:-${kak_buffile}}"
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}"/kak-src-outline.XXXXXXXX)"
    tags="${tmpdir}"/tags
    output="${tmpdir}"/fifo
    mkfifo "${output}"
    ctags --fields=akKzsZSt --excmd=number -f "${tags}" "${buffile}"

    sortexp="(<or> "
    for g in "scope" "access" "kind" "name"; do
        sortexp="${sortexp}"'(<> (if (eq? $'"${g}"' #f) "" $'"${g}"') (if (eq? &'"${g}"' #f) "" &'"${g}"'))'
    done
    sortexp="${sortexp})"

    ( readtags -t "${tags}" -S "${sortexp}" -el | awk -F $'\t' '
        BEGIN {
            prev_scope = ""
            prev_access = ""
            prev_kind = ""
            first_out = 1
        }
        {
            name = $1
            line = $3; line = substr(line, 0, length(line)-2)

            kind = ""
            scope = ""
            access = ""
            typeref = ""
            signature = ""
            for (i=4; i<=NF; i++) {
                if        (sub("^kind:", "", $i)) {
                    kind = $i
                } else if (sub("^scope:", "", $i)) {
                    scope = $i
                } else if (sub("^access:", "", $i)) {
                    access = $i
                } else if (sub("^typeref:", "", $i)) {
                    typeref = $i
                } else if (sub("^signature:", "", $i)) {
                    signature = $i
                }
            }

            if (prev_scope != scope || prev_access != access || prev_kind != kind || first_out) {
                start_print = 0
                if (!first_out) {
                    print ""
                } else {
                    start_print = 1
                }
                first_out = 0
                indent = ""

                if (prev_scope != scope || start_print) {
                    start_print = 1
                    if (scope != "")
                        print indent scope
                    prev_scope = scope
                }
                if (scope != "")
                    indent = indent " "

                if (prev_access != access || start_print) {
                    start_print = 1
                    if (access != "")
                        print indent access
                    prev_access = access
                }
                if (access != "")
                    indent = indent " "

                if (prev_kind != kind || start_print) {
                    start_print = 1
                    if (kind != "")
                        print indent kind
                    prev_kind = kind
                }
                if (kind != "")
                    indent = indent " "
            }
            out = indent name "\t"
            if (typeref != "")
                out = out typeref "\t"
            if (signature != "")
                out = out signature "\t"
            print out "#" line
        }
    ' > ${output} 2>&1 & ) > /dev/null 2>&1 < /dev/null

    valid_buffile="$(tr -c '[:alnum:]' '-' <<<"${buffile}" | sed 's/-\+/-/g; s/^-//; s/-$//')"
    printf %s\\n "evaluate-commands -try-client %opt{toolsclient} %{
        edit! -fifo ${output} *src-outline-${valid_buffile}*
        set-option buffer filetype src-outline
        set-option window tabstop 1
        hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r ${tmpdir} } }

        try %{ remove-hooks buffer src-outline-hooks-${valid_buffile} }
        hook -group src-outline-hooks-${valid_buffile} buffer NormalKey <ret> %{ evaluate-commands %{
            try %{
                execute-keys 'xs\d+$<ret>'
                evaluate-commands -try-client %opt{jumpclient} -verbatim -- \
                    edit -existing ${buffile} %reg{0}
                try %{ focus %opt{jumpclient} }
            }
        }}
    }"
}}

}
