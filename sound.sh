#!/bin/bash

# Включаем типо strict mode
set -euo pipefail

readonly SCRIPT_NAME=$(basename "$0")
readonly ROOT=$(dirname "$0")

# Импорты модулей
source "$ROOT/config.sh"
source "$ROOT/utils.sh"

# Справочная информация по данному скрипту
usage() {
    cat << EOF
    Usage: $SCRIPT_NAME [OPTIONS] <required_arg>

    Description of what this script does.

    OPTIONS:
        -h, --help          Show this help message
        -d, --debug         Enable debug mode
        -l, --loop          Enable loop mode

EOF
}

FILES=()
DEBUG=false
LOOP=false

play_audio() {
    local file="$1"
    local pid_file="$2"

    if [[ ! -f "$file" ]]; then
        __msg_error "Файл '$file' не найден."
        return 240
    fi

    # если есть старый PID — попробуем остановить
    stop_audio "$pid_file"

    if command -v afplay &>/dev/null; then
        echo "🚀 Запускаю $(basename "${selected_file%%.*}")..."

        if [[ $LOOP ]]; then
            while true; do
                # Сохраняем PID
                echo $! > "$pid_file"
                afplay "$file" &>/dev/null
            done &
        else
            # Сохраняем PID
            echo $! > "$pid_file"
            afplay "$file" &>/dev/null
        fi
    fi
}

stop_audio() {
    local pid_file="$1"

    # Проверяем сначала наличие файла с PID
    if [[ ! -f "$pid_file" ]]; then
        $DEBUG && __msg_error "Файл с PID отсутствует"
        return 0 
    fi

    local pid=$(<"$pid_file")

    if [[ -z $pid ]]; then
        $DEBUG && __msg_error "PID отсутствует"
        rm -f "$pid_file"
        return 0
    fi

    if ! kill -0 "$pid" &>/dev/null; then
        $DEBUG && echo "Процесс с PID $pid не найден. Удаляю PID-файл."
        rm -f "$pid_file"
        return 0
    fi

    # Получаем PID-ы дочерних процессов данного скрипта
    local child_pids=$(pgrep -P "$pid")

    # Заверашем дочерние процессы
    if [ -n "$child_pids" ]; then
        kill -SIGTERM "$child_pids"
    fi

    # Завершаем основной процесс
    kill -SIGTERM "$pid"
    rm -f "$pid_file"

    echo "💔 Конец вечеринке..."
    return 0
}

status_audio() {
    local pid_file="$1"

    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" &>/dev/null; then
            echo "Аудио играет (PID $pid)."
        else
            $DEBUG && echo "PID-файл есть, но процесс $pid не найден."
        fi
    else
        echo "Аудио сейчас не запущено."
    fi
}

list_files() {
    local directory="$1"

    if [[ ! -d $directory ]]; then
        __msg_error "Путь не ведет к папке."
        return 240
    fi

    local index=1
    for file in "$directory"/*.{mp3,wav,ogg,flac}; do
        if [[ -f "$file" ]]; then
            FILES+=("$file")
            
            if [[ ${#FILES[@]} -eq 1 ]]; then
                echo "Выбирай, что есть тут ($directory):"    
            fi
            
            local basename_file="${file##*/}" 
            echo "  [$index] ${basename_file%%.*}"
            ((index++))
        fi
    done
    
    if [[ ${#FILES[@]} -eq 0 ]]; then
        __msg_error "Файлы не найдены."
        return 240
    fi
}

select_file() {
    local pid_file="$1"

    read -p "Введите номер файла 👉 " NUMBER 
    if [[ "$NUMBER" =~ ^[0-9]+$ ]] && (( NUMBER >= 1 && NUMBER <= ${#FILES[@]} )); then
        local selected_file=${FILES[$((NUMBER-1))]}
        play_audio "$selected_file" "$pid_file"
    else
        echo "🫤 Неверный номер."
    fi
}

show_prompt() {
    while true; do
        read -p "(list/stop/status): " INPUT

        case "$INPUT" in
            stop)
                stop_audio "$AUDIO_PID_FILE"
                ;;
            status)
                status_audio "$AUDIO_PID_FILE"
                ;;
            list)
                list_files "$MUSIC_DIR" && select_file "$AUDIO_PID_FILE"
                ;;
        esac
    done
}

main() {
    clear
    $DEBUG && echo -e "🛠  DEBUG MODE  🛠\n"
    
    if [[ ! -f $AUDIO_PID_FILE ]]; then
        list_files "$MUSIC_DIR" && select_file "$AUDIO_PID_FILE" && show_prompt
    else
        show_prompt
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--debug)
            DEBUG=true
            break
            ;;
        -l|--loop)
            LOOP=true
            break
            ;;
        *)
            break
            ;;
    esac
done

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi