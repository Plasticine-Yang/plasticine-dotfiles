# shellcheck shell=sh
# Keep real OS utilities, while excluding preinstalled runtimes and managers.
# Runtime tests explicitly supply their own Node/fnm/brew/Cargo fixtures.
plasticine_test_system_path() {
    plasticine_test_bin=$1
    mkdir -p "$plasticine_test_bin"
    for plasticine_test_tool in awk cat chmod cmp cp cut date dd dirname env find \
        grep head id ln ls mkdir mktemp mv od readlink rm sed sh sort stat tail \
        touch tr uname wc; do
        plasticine_test_program=$(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$plasticine_test_tool" 2>/dev/null || true)
        case $plasticine_test_program in
            /*) ln -s "$plasticine_test_program" "$plasticine_test_bin/$plasticine_test_tool" ;;
        esac
    done
}
