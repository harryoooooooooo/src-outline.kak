# src-outline: A simple wrapper of Universal Ctags.

# The plugin doesn't and won't provide any language specific feature.
# It is intended to only process the output of ctags as general as possible.

hook global KakBegin .* %sh{
    if ! command -v ctags > /dev/null 2>&1; then
        echo "echo -debug Universal Ctags is needed for src-outline command"
        exit
    fi
    echo "require-module src-outline"
}

provide-module src-outline %{

declare-option -docstring "name of the client in which utilities display information" \
    str toolsclient
declare-option -docstring "name of the client in which all source code jumps will be executed" \
    str jumpclient

define-command -docstring '
src-outline: Show the outline of the source file.
Press <ret> to jump to the line.' \
    -params 0 src-outline %{ evaluate-commands %sh{
    output=$(mktemp -d "${TMPDIR:-/tmp}"/kak-src-outline.XXXXXXXX)/fifo
    mkfifo ${output}
    ( ctags -f - --fields=aiKsZt --excmd=number --extras=+q "${kak_buffile}" |
        sed -E 's/^([^\t]+\t).+(\t[0-9]+);"\t([^\t]+)/\1\3\2/g' |
        awk -F $'\t' '{
            line = $3
            type = $2
            name = $1
            short_name = $1  # The symbol name without class/namespace-qualified
            scope_type = ""
            scope_name = ""
            access = ""
            addi = ""
            for (i=4; i<=NF; i++) {
                if (match($i, "^scope:[^:]+:")) {
                    l = length("scope:")
                    scope_type = substr($i, l+1, RLENGTH-l-1)
                    scope_name = substr($i, RLENGTH+1)

                    # name should have prefix "<scope_name><separator>".
                    # Otherwise it is a line without class/namespace-qualified
                    # and we should skip it.
                    if (substr(name, 1, length(scope_name)) != scope_name)
                        next
                    short_name = substr(name, length(scope_name)+1)
                    # We hard code some common separators here.
                    if (!sub("^\\.", "", short_name) &&
                        !sub("^::", "", short_name) &&
                        !sub("^\\\\", "", short_name))
                        next
                } else if (match($i, "^access:")) {
                    access = substr($i, RLENGTH+1)
                    if      (access == "private")   access = "-"
                    else if (access == "protected") access = "!"
                    else if (access == "public")    access = "+"
                    else {
                        access = ""
                        addi = addi "\t" $i
                    }
                } else {
                    addi = addi "\t" $i
                }
            }
            id = "(" type ") " name
            scope_id = "(" scope_type ") " scope_name
            sorter = "[" access "]" "(" type ")" "{" short_name "}"
            pretty_name = access "(" type ") " short_name
            print sorter "\t" id "\t" scope_id "\t" line ":\t" pretty_name addi}' |
        LANG=C sort |
        column -t --tree-id 2 --tree-parent 3 --tree 5 -H 1,2,3 -s $'\t' |
        sed 's/ *$//g' > ${output} 2>&1 & ) > /dev/null 2>&1 < /dev/null

    printf %s\\n "evaluate-commands -try-client %opt{toolsclient} %{
        edit! -fifo ${output} *src-outline*
        hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r $(dirname ${output}) } }

        try %{ remove-hooks buffer src-outline-hooks }
        hook -group src-outline-hooks buffer NormalKey <ret> %{ evaluate-commands %{
            try %{
                execute-keys 'xs^\d+<ret>'
                evaluate-commands -try-client %opt{jumpclient} -verbatim -- \
                    edit -existing ${kak_buffile} %reg{0}
                try %{ focus %opt{jumpclient} }
            }
        }}
    }"
}}

}
