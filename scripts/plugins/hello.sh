function hello() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: hello"
        return 0
    fi
    echo "Hello, World!"
}
