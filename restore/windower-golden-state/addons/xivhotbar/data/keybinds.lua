-- Windower modifiers; the mapper adds the chat-closed guard.
-- Six shared row chords; slots 11/12 remain mouse-only in each environment.
return {
    -- Left, bottom to top: plain numbers, Shift, Ctrl.
    {'1', '2', '3', '4', '5', '6', '7', '8', '9', '0'},
    {'~1', '~2', '~3', '~4', '~5', '~6', '~7', '~8', '~9', '~0'},
    {'^1', '^2', '^3', '^4', '^5', '^6', '^7', '^8', '^9', '^0'},
    -- Right, bottom to top: Alt, Ctrl+Shift, Ctrl+Alt. No triple modifiers.
    {'!1', '!2', '!3', '!4', '!5', '!6', '!7', '!8', '!9', '!0'},
    {'^~1', '^~2', '^~3', '^~4', '^~5', '^~6', '^~7', '^~8', '^~9', '^~0'},
    {'^!1', '^!2', '^!3', '^!4', '^!5', '^!6', '^!7', '^!8', '^!9', '^!0'},
}
