#!/bin/bash
# ============================================================
# Termux Debian 容器一键安装脚本
# ============================================================

set -Eeuo pipefail

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
  B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
else
  R=''; G=''; Y=''; B=''; C=''; N=''
fi

info(){ echo -e "${B}[INFO]${N} $1"; }
ok(){ echo -e "${G}[OK]${N} $1"; }
warn(){ echo -e "${Y}[WARN]${N} $1"; }
err(){ echo -e "${R}[ERROR]${N} $1" >&2; }
step(){ echo -e "${C}[STEP]${N} $1"; }

on_error(){
  local line="$1"
  err "执行失败：第 ${line} 行"
  echo "可尝试：" >&2
  echo "  1. 检查网络" >&2
  echo "  2. 执行 termux-change-repo 更换软件源" >&2
  echo "  3. 重新运行本脚本" >&2
}
trap 'on_error $LINENO' ERR

usage(){
  cat <<'EOF'
用法:
  bash install_container_only.sh [选项]

选项:
  -h, --help         显示帮助
  --skip-update      跳过 pkg update
  --force-nb         如果 nb 命令已存在，直接覆盖，不备份

安装完成后进入 Debian 容器:
  nb

执行 Debian 内命令:
  nb -- bash -lc 'cat /etc/os-release'
EOF
}

confirm_continue(){
  local prompt="$1"
  local answer=""
  if [ ! -t 0 ]; then
    return 0
  fi
  read -r -p "$prompt" answer || true
  case "$answer" in
    n|N|no|NO|No) return 1 ;;
    *) return 0 ;;
  esac
}

SKIP_UPDATE=false
FORCE_NB=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --skip-update)
      SKIP_UPDATE=true
      ;;
    --force-nb)
      FORCE_NB=true
      ;;
    *)
      err "未知选项: $1"
      usage
      exit 2
      ;;
  esac
  shift
done

[ -t 1 ] && clear || true
echo "========================================"
echo -e "${C}  Termux Debian 容器一键安装${N}"
echo "========================================"
echo ""

if [ -z "${TERMUX_VERSION:-}" ] && [ ! -d "/data/data/com.termux" ]; then
  err "请在 Termux 运行"
  exit 1
fi

if ! command -v pkg >/dev/null 2>&1; then
  err "未找到 pkg 命令，请确认当前环境是 Termux"
  exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
  aarch64|arm64)
    ok "当前架构: $ARCH"
    ;;
  *)
    warn "当前架构: $ARCH，不是常见 Android arm64 架构"
    confirm_continue "仍然继续? [Y/n] " || exit 1
    ;;
esac

PREFIX_DIR="${PREFIX:-/data/data/com.termux/files/usr}"
BIN_DIR="$PREFIX_DIR/bin"
DEBIAN_ROOT="$PREFIX_DIR/var/lib/proot-distro/installed-rootfs/debian"
NB_CMD="$BIN_DIR/nb"
NB_MARKER="# nb-debian-container-launcher"

check_space(){
  local avail_kb=""
  avail_kb=$(df -Pk "$PREFIX_DIR" 2>/dev/null | awk 'NR==2 {print $4}') || true
  if [ -n "$avail_kb" ] && [ "$avail_kb" -lt 1048576 ]; then
    warn "可用空间小于 1GB，Debian 安装可能失败"
    confirm_continue "仍然继续? [Y/n] " || exit 1
  fi
}

write_nb_launcher(){
  mkdir -p "$BIN_DIR"

  if [ -e "$NB_CMD" ]; then
    if grep -qF "$NB_MARKER" "$NB_CMD" 2>/dev/null; then
      info "检测到旧 nb 启动器，将更新"
    elif [ "$FORCE_NB" = true ]; then
      warn "检测到已有 nb 命令，按 --force-nb 要求直接覆盖"
    else
      local backup="${NB_CMD}.bak.$(date +%Y%m%d-%H%M%S)"
      warn "检测到已有 nb 命令，已备份到：$backup"
      mv "$NB_CMD" "$backup"
    fi
  fi

  cat > "$NB_CMD" <<'NBEOF'
#!/bin/bash
# nb-debian-container-launcher
set -e

if ! command -v proot-distro >/dev/null 2>&1; then
  echo "[ERROR] 未找到 proot-distro，请先运行安装脚本" >&2
  exit 1
fi

exec proot-distro login debian "$@"
NBEOF
  chmod +x "$NB_CMD"
}

echo ""
step "[1/5] 检查可用空间..."
check_space
ok "空间检查完成"

echo ""
step "[2/5] 更新 Termux 包索引..."
if [ "$SKIP_UPDATE" = true ]; then
  warn "已按参数跳过 pkg update"
else
  pkg update -y
  ok "Termux 包索引已更新"
fi

echo ""
step "[3/5] 安装/检查 proot-distro..."
if command -v proot-distro >/dev/null 2>&1; then
  ok "proot-distro 已安装"
else
  pkg install -y proot-distro
  ok "proot-distro 安装完成"
fi

echo ""
step "[4/5] 安装/检查 Debian 容器..."
if [ -d "$DEBIAN_ROOT" ]; then
  warn "Debian 容器已存在，跳过安装"
else
  proot-distro install debian
  ok "Debian 容器安装完成"
fi

echo ""
step "[5/5] 创建 nb 启动命令..."
write_nb_launcher
ok "nb 命令已创建：$NB_CMD"

echo ""
echo "========================================"
echo -e "${G}  容器安装完成！${N}"
echo "========================================"
echo ""
echo "进入 Debian 容器："
echo "  nb"
echo ""
echo "执行 Debian 内命令："
echo "  nb -- bash -lc 'cat /etc/os-release'"
echo ""
echo "常用管理命令："
echo "  proot-distro login debian    # 原始进入命令"
echo "  proot-distro remove debian   # 删除 Debian 容器"
echo ""
