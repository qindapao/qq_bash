# config/words.sh — 箴言词库
[[ -n "${_STRAFE_WORDS_SH:-}" ]] && return 0
_STRAFE_WORDS_SH=1
. "$STRAFE_PROJ_DIR/config/const.sh"

declare -a WORD_LIST=(
    'Time is money, my friend!'
    'Stay hungry, stay foolish.'
    'Hello, world!'
    'To be or not to be.'
    'All you need is love.'
    'I am your father.'
    'May the force be with you.'
    'Keep calm and carry on.'
    'Just do it.'
    'Less is more.'
    'Talk is cheap. Show me the code.'
    'Premature optimization is the root of all evil.'
    'The best way out is always through.'
    'Code is poetry.'
    'Simplicity is the soul of efficiency.'
)

if (( LOCALE_UTF8 )) ; then
    WORD_LIST+=(
        'Stay curious, keep learning.'
    )
fi

