# config/words.sh — 箴言词库
declare -gA _STRAFE_LOADED
(( _STRAFE_LOADED[words]++ )) && return 0
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

    # 各民族的老话（英文转写，皆为大白话版本的谚语）
    'Rome was not built in a day.'
    'Fortune favors the bold.'
    'A rolling stone gathers no moss.'
    'Measure twice, cut once.'
    'Trust, but verify.'
    'It takes a village.'
    'May the road rise to meet you.'
    'Smooth seas never made a skilled sailor.'
    'The pen is mightier than the sword.'
    'Patience is a key that opens many doors.'
    'A fall into a pit, a gain in wit.'
    'He who asks is a fool for five minutes.'
    'Small steps also move mountains.'
    'Better to light a candle than curse the dark.'
    'The stars are not in a hurry.'

    # 写代码的人爱说的俏皮话
    'It works on my machine.'
    'There is no place like 127.0.0.1.'
    'Commit early, commit often.'
    'Make it work, then make it fast.'
    'Slow is smooth, smooth is fast.'
    'Read the docs, they are cheaper.'
    'Ship it, then fix it.'
    'Never debug angry.'
    'One more level, then sleep.'

    # 一点胡思乱想
    'Cats are liquid.'
    'Every pawn is a potential queen.'
    'Practice makes progress.'
    'A watched pot never boils.'
    'Breathe in, breathe out.'
)

# 词库约束（新增词条时必须满足）：
#   - 只用可打印 ASCII：终端里宽度确定，不会因双宽字符把整行顶歪（宪法第 5 节）；
#   - 不含单引号：词条本身用单引号包裹，省去转义；
#   - 长度受控：超过 SCREEN_W-4 的词条会被刷字逻辑直接跳过（白掉一次刷新）。
# 测试 test/strafe_bash/test_words.sh 会强制校验以上约束。

if (( LOCALE_UTF8 )) ; then
    WORD_LIST+=(
        'Stay curious, keep learning.'
    )
fi

