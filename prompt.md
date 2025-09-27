我需要你帮我完成一个python脚本的剩余部分（基本上是主流程和视频选择），我已经封装了很多函数供主流程调用，整个脚本用于实现“节能的视频壁纸”。

这个脚本将控制视频壁纸的产生、播放、暂停、更换，它用一些系统调用来探测当前状态是否符合视频播放的条件，如果符合才会播放，否则保持暂停。这个脚本将在Deepin下运行，它将按照系统时间让4个视频在不同的时间区间内循环播放。

## 程序流程：

先检测脚本用到的各项命令行工具是否存在，存在则继续。

1. 运行用于启动mpv的shell脚本，它会运行mpv并创建mpv.pid文件，里面有pid
2. 切换窗口层级，将mpv放在桌面窗口底下作为壁纸。
3. 每1秒循环
3.1. 根据当前的视频和系统时间和设计的时间区间决定是否更换视频。
    如果是则发送指令给mpv的ipc， 如果否则无事发生。
3.2. 检查视频能否播放
    如果能，则判断当前是否在播放，如果在播放则什么都不做，如果不在播放则发送指令给mpv的ipc使它播放。
    如果否，则判断当前是否在播放，如果在播放则发送指令给mpv的ipc使它暂停播放，如果不在播放则什么都不做。

在程序因为任何原因退出时，先还原窗口层级，再根据mpv的pid杀死mpv进程，并删除mpv.pid和ipc_server文件。

## 何时播放视频？

首先，其他时机需要暂停视频。

只有满足以下条件，才会播放视频：
1. 桌面上没有任何应用程序窗口
2. 屏幕正在显示，屏幕不处于锁屏和熄屏的状态下
3. 5分钟内移动过鼠标和操作键盘，如果上次移动鼠标和操作键盘的时间距离现在超过5分钟，则不能播放视频

## 视频文件与循环播放时机
一共有4段视频，每段视频时长几分钟。4个视频文件，其中：
- DARK01_20250703_v10_sdr_4k_rate12000_240p_t2160_grover74_tsa_nclc111.mov，是太阳升起之前的
- LIGHT02_20250613_V2_sdr_4k_rate12000_240p_t2160_grover74_tsa_MTE-Modified.mov，是太阳直射的
- LIGHT01_20250623_V3_sdr_4k_rate12000_240p_t2160_grover74_tsa_nclc111.mov，是太阳落入地平线之前的
- DARK02_20250719_V1_FRC_240fps_sdr_4k_rate12000_240p_t2160_grover74_tsa_nclc111.mov，是夜晚的

第一段视频为太阳升起之前的，在24小时制的05:00:00~07:59:59循环播放。
第二段视频为太阳直射的，在24小时制的08:00:00~16:59:59循环播放。
第三段视频为太阳落入地平线之前的，在24小时制的17:00:00~19:59:59循环播放。
第四段视频为夜晚的，在24小时制的20:00:00~04:59:59循环播放。

## 我封装的那些函数

我已经对那些函数进行了单独的测试，运行起来没有问题。

运行用于启动mpv的shell脚本后，记得延迟半秒等待mpv窗口出现。

由于我没有封装运行用于启动mpv的shell脚本的函数，这里我把shell脚本文件名和内容告诉你，你就知道运行哪个文件和传递什么参数了。
文件名：`mpv.sh`
内容：
```
nohup mpv --input-ipc-server="ipc_server" --no-audio --panscan=1 --pause --hwdec="auto" --no-osc --no-osd-bar --no-input-default-bindings --no-input-cursor --cursor-autohide=no --no-window-dragging --no-border --no-taskbar-progress --keep-open=yes --loop-file=inf --idle=yes --input-vo-keyboard=no --x11-bypass-compositor=no --focus-on="never" --ontop=no --stop-screensaver=no --no-config --no-keepaspect-window --force-window=immediate "$1" > nohup.log 2>&1 &
pid=$!
echo "$pid" > mpv.pid
```

这些封装的函数中，`check_no_app_window()`函数我留了一个todo，它需要根据mpv的窗口id和桌面窗口的窗口id排除这俩窗口。桌面窗口的窗口id全局有，用这个id是稳定的，自行判断是不稳定的。

## 当前python脚本的代码

```
import dbus
import subprocess
import sys
import re
import shutil
import json
import socket
import time
from typing import List, Tuple, Union, Set, Optional, Dict, Any
import os
import signal
import atexit
import shlex
from dataclasses import dataclass

# 全局缓存（幂等支持）
DESKTOP_WIN_ID: Optional[str] = None
EXIT_HOOK_INSTALLED = False

# 修改/还原所需的原始属性缓存
@dataclass
class WindowProps:
    window_type: Optional[List[str]]  # 例如 ['_NET_WM_WINDOW_TYPE_DESKTOP']
    wm_state: Optional[Set[str]]      # 例如 {'_NET_WM_STATE_BELOW', ...}
    opacity: Optional[int]            # _NET_WM_WINDOW_OPACITY
    opaque_region: Optional[str]      # _NET_WM_OPAQUE_REGION 的原始数值串，例如 "0, 0, 1920, 1080"
    geometry: Optional[Tuple[int, int, int, int]] = None

# 保存当前会话已修改的窗口属性（用于还原）
ORIGINAL_DESKTOP_PROPS: Optional[WindowProps] = None
ORIGINAL_MPV_PROPS: Dict[str, WindowProps] = {}  # key: mpv_window_id
APPLIED: bool = False

# 常量
DDE_DESKTOP_WM_CLASS_1 = "dde-shell"
DDE_DESKTOP_WM_CLASS_2 = "org.deepin.dde-shell"
REQUIRED_CMDS = ["xprop", "wmctrl", "xwininfo"]
OPACITY_MAGIC = 4252017622  # DDE 特定值，触发合成器以 ARGB 混合
STATE_FLAGS_WE_TOUCH = {
    "_NET_WM_STATE_ABOVE": "above",
    "_NET_WM_STATE_BELOW": "below",
    "_NET_WM_STATE_STICKY": "sticky",
    "_NET_WM_STATE_SKIP_TASKBAR": "skip_taskbar",
    "_NET_WM_STATE_SKIP_PAGER": "skip_pager",
}

def check_lock_screen() -> bool:
    """
    检测是否锁屏，返回一个布尔值，如果已经锁屏则为True，未锁屏则为False
    """
    try:
        # 获取系统D-Bus连接
        bus = dbus.SessionBus()

        # 获取LockFront1服务的代理对象
        proxy = bus.get_object('org.deepin.dde.LockFront1', '/org/deepin/dde/LockFront1')

        # 获取Properties接口
        properties_iface = dbus.Interface(proxy, 'org.freedesktop.DBus.Properties')

        # 获取Visible属性值
        visible = properties_iface.Get('org.deepin.dde.LockFront1', 'Visible')

        return bool(visible)

    except dbus.exceptions.DBusException as e:
        # 如果D-Bus服务不可用或其他D-Bus相关错误，假设未锁屏
        print(f"D-Bus error: {e}")
        return False
    except Exception as e:
        # 处理其他异常
        print(f"Error checking lock screen: {e}")
        return False

def check_blank_screen() -> bool:
    """
    检测黑屏，返回一个布尔值，如果已经黑屏则返回True,否则返回False。

    该函数通过执行 linux 命令 `xset q` 并解析其输出来工作。
    它专门查找 "Monitor is Off" 字符串。

    注意: 此函数仅在带有 X11 的 Linux 系统上有效，且需要安装 `xset` 工具。
    在 Windows、macOS 或没有图形环境的服务器上将无法正常工作。
    """
    # 首先，检查是否在 Linux 系统上，因为 xset 是 Linux X11 特有的
    if not sys.platform.startswith('linux'):
        print("Warning: This function is designed for Linux with X11.")
        return False

    try:
        # 定义要执行的命令
        command = ["xset", "q"]

        # 执行命令并捕获其输出
        # - capture_output=True: 捕获 stdout 和 stderr
        # - text=True: 将 stdout 和 stderr 解码为字符串（使用默认编码）
        # - check=False: 如果命令返回非零退出码，不抛出异常，以便我们手动处理
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False
        )

        # 如果命令执行失败（例如，在没有 X server 的 ssh 会话中），其返回码不为 0
        if result.returncode != 0:
            # 打印错误信息以便调试，但函数仍返回 False
            print(f"无法执行 'xset q'。错误: {result.stderr.strip()}")
            return False

        # 在命令的 stdout 输出中查找 "Monitor is Off"
        # 'in' 操作符会返回一个布尔值，可以直接返回这个结果
        return "Monitor is Off" in result.stdout

    except FileNotFoundError:
        # 如果系统中没有安装 'xset' 命令
        print("错误: 未找到 'xset' 命令。请确保 x11-xserver-utils 或类似包已安装。")
        return False
    except Exception as e:
        # 捕获其他任何意外异常
        print(f"发生未知错误: {e}")
        return False

def xprintidle() -> int:
    """
    这个函数会返回一个数字，这个数字是指：当前时间，距离上一次操作键盘和鼠标的持续时间。
    有时也称为“用户空闲时间”、“无操作时间”。单位是毫秒。

    实现方式：
    通过调用外部的 xprintidle.py 脚本来获取这个值。
    """
    try:
        # 1. 构建命令
        # 使用 sys.executable 可以确保我们用的是当前运行这个脚本的同一个 Python 解释器，
        # 这比直接用 "python" 命令更可靠。
        command = [sys.executable, "xprintidle.py"]

        # 2. 执行命令
        # subprocess.run 是执行外部命令的标准方法。
        # - capture_output=True: 捕获子进程的标准输出和标准错误。
        # - text=True: 将捕获的输出解码为文本字符串（使用默认编码）。
        # - check=True: 如果命令返回非零退出码（表示执行出错），则会引发一个 CalledProcessError 异常。
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True
        )

        # 3. 处理输出
        # result.stdout 包含了脚本打印到标准输出的内容。
        # 通常输出会带有一个换行符，所以使用 .strip() 来移除首尾的空白字符。
        output_str = result.stdout.strip()

        # 4. 转换并返回结果
        # 将字符串转换为整数并返回。
        return int(output_str)

    except FileNotFoundError:
        # 如果 "python" 解释器或 "xprintidle.py" 脚本找不到，会触发此异常。
        raise RuntimeError("依赖脚本 'xprintidle.py' 未找到。")

    except subprocess.CalledProcessError as e:
        # 如果 xprintidle.py 脚本执行时出错（比如，它内部有语法错误或运行时错误），会触发此异常。
        print(f"错误：执行 'xprintidle.py' 脚本失败。")
        print(f"返回码: {e.returncode}")
        print(f"错误输出: {e.stderr.strip()}")
        raise RuntimeError(f"执行 'xprintidle.py' 时出错: {e.stderr.strip()}")

    except ValueError:
        # 如果脚本的输出不是一个有效的数字（比如是空字符串或包含了文本），int() 转换会失败。
        raise ValueError(f"无法将脚本输出 '{output_str}' 转换为整数。")

def check_no_app_window() -> bool:
    """
    检查屏幕上是否无应用程序窗口在显示：
    - 跳过类型包含 _NET_WM_WINDOW_TYPE_DOCK / _NET_WM_WINDOW_TYPE_DESKTOP 的系统窗口
    - 对其他窗口检查 _NET_WM_STATE 是否包含 _NET_WM_STATE_HIDDEN
    - 若有任一非系统窗口未隐藏，则返回 False；否则返回 True
    - todo 需要排除桌面窗口和mpv窗口，因为这俩窗口确实是一直显示的，而且窗口类型会变化
    """
    # 依赖 xprop
    if shutil.which("xprop") is None:
        # 无法判断，按“保守”处理：认为可能有窗口在显示
        return False

    def run_cmd(args, timeout=3) -> str | None:
        try:
            cp = subprocess.run(
                args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=timeout
            )
            if cp.returncode != 0:
                return None
            return cp.stdout
        except Exception:
            return None

    # 1) 获取所有被 WM 管理的窗口列表
    out = run_cmd(["xprop", "-root", "_NET_CLIENT_LIST"])
    if out is None:
        # 读不到根属性，无法确认，按可能有窗口处理
        return False

    # 解析 window id（十六进制形式 0x...）
    window_ids = re.findall(r"0x[0-9a-fA-F]+", out)
    # 没有任何客户端窗口 => 屏幕上无应用程序窗口显示
    if not window_ids:
        return True

    # 2) 遍历每个窗口，读取类型与状态
    SYSTEM_TYPES = {"_NET_WM_WINDOW_TYPE_DOCK", "_NET_WM_WINDOW_TYPE_DESKTOP"}

    for wid in window_ids:
        props = run_cmd(["xprop", "-id", wid, "_NET_WM_WINDOW_TYPE", "_NET_WM_STATE"])
        if props is None:
            # 窗口可能刚好销毁/不可读，跳过
            continue

        types = []
        states = []

        for line in props.splitlines():
            if line.startswith("_NET_WM_WINDOW_TYPE"):
                idx = line.find("=")
                if idx != -1:
                    vals = [x.strip() for x in line[idx + 1 :].split(",") if x.strip()]
                    types = vals
            elif line.startswith("_NET_WM_STATE"):
                idx = line.find("=")
                if idx != -1:
                    raw = line[idx + 1 :].strip()
                    if raw and raw != "0x0":
                        vals = [x.strip() for x in raw.split(",") if x.strip()]
                        states = vals

        # 跳过系统窗口
        if any(t in SYSTEM_TYPES for t in types):
            continue

        # 非系统窗口若未隐藏，则说明有应用窗口显示中
        if "_NET_WM_STATE_HIDDEN" not in states:
            return False

    # 所有非系统窗口均隐藏或不存在
    return True

# 三个预置命令数据（直接作为 data 传给 send_mpv_ipc）
MPV_CMD_PLAY = {"command": ["set_property", "pause", False]}   # 播放/继续
MPV_CMD_PAUSE = {"command": ["set_property", "pause", True]}   # 暂停
MPV_CMD_LOADFILE = {"command": ["loadfile", "", "replace"]}    # 更换视频：发送前把第二项改为目标路径

def send_mpv_ipc(ipc_path: str, data: Union[Dict[str, Any], str], timeout: float = 2.0) -> Tuple[bool, Optional[Dict[str, Any]]]:
    """
    连接 mpv 的 --input-ipc-server，发送一条消息并等待对应回复。
    参数:
        ipc_path: mpv 启动时 --input-ipc-server 指定的 Unix socket 路径 (e.g. "/tmp/mpv.sock")
        data: dict 或 JSON 字符串。如果是 dict 且无 request_id，则自动注入。
        timeout: 连接与读取的超时时间(秒)
    返回:
        (ok, reply)
        ok: True 表示 mpv 返回 {"error": "success"}；False 表示失败或超时
        reply: 解析后的 mpv 回复字典（若低层失败或超时则为 None）
    """
    req_id = None

    # 规范化负载，并尽量注入 request_id 以便匹配响应
    if isinstance(data, dict):
        if 'request_id' not in data:
            req_id = int(time.time() * 1000) & 0x7FFFFFFF
            data = {**data, 'request_id': req_id}
        else:
            req_id = data.get('request_id')
        payload = json.dumps(data, separators=(',', ':'), ensure_ascii=False) + '\n'

    elif isinstance(data, str):
        obj = None
        try:
            obj = json.loads(data)
        except Exception:
            obj = None

        if isinstance(obj, dict):
            if 'request_id' not in obj:
                req_id = int(time.time() * 1000) & 0x7FFFFFFF
                obj['request_id'] = req_id
            else:
                req_id = obj.get('request_id')
            payload = json.dumps(obj, separators=(',', ':'), ensure_ascii=False) + '\n'
        else:
            payload = data if data.endswith('\n') else data + '\n'
            req_id = None
    else:
        raise TypeError("data 必须是 dict 或 JSON 字符串")

    # 连接并发送
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(ipc_path)
            s.sendall(payload.encode('utf-8'))

            # 读取到对应回复为止（过滤事件）
            buf = b''
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    buf += chunk
                    while b'\n' in buf:
                        line, buf = buf.split(b'\n', 1)
                        if not line.strip():
                            continue
                        try:
                            msg = json.loads(line.decode('utf-8', errors='replace'))
                        except Exception:
                            continue
                        if isinstance(msg, dict) and 'event' in msg:
                            # 跳过异步事件
                            continue
                        if req_id is not None and isinstance(msg, dict):
                            if msg.get('request_id') != req_id:
                                continue
                        if isinstance(msg, dict) and 'error' in msg:
                            ok = (msg.get('error') == 'success')
                            return ok, msg
                        # 兜底：无 error 字段也直接返回
                        return True, msg
                except socket.timeout:
                    break
            return False, None
    except FileNotFoundError:
        return False, {'error': 'socket_not_found', 'socket': ipc_path}
    except ConnectionRefusedError:
        return False, {'error': 'connection_refused', 'socket': ipc_path}
    except Exception as e:
        return False, {'error': type(e).__name__, 'message': str(e)}

# --------------切换窗口层级开始---------------------
def _get_window_geometry(id_hex: str) -> Tuple[int, int, int, int]:
    """
    返回 (x, y, w, h) —— 绝对坐标与大小
    """
    cp = _run(["xwininfo", "-id", id_hex])
    if cp.returncode != 0:
        raise RuntimeError(f"xwininfo 失败: {cp.stderr}")
    out = cp.stdout
    x = int(re.search(r"Absolute upper-left X:\s*(-?\d+)", out).group(1))
    y = int(re.search(r"Absolute upper-left Y:\s*(-?\d+)", out).group(1))
    w = int(re.search(r"Width:\s*(\d+)", out).group(1))
    h = int(re.search(r"Height:\s*(\d+)", out).group(1))
    return (x, y, w, h)

def _wmctrl_move_resize(id_hex: str, x: int, y: int, w: int, h: int):
    # gravity 用 0，常见 WM 下等同于默认
    _run(["wmctrl", "-i", "-r", id_hex, "-e", f"0,{x},{y},{w},{h}"])

def _check_env():
    if os.environ.get("XDG_SESSION_TYPE", "x11") != "x11":
        print("[warn] 当前似乎不是 X11 会话（XDG_SESSION_TYPE != x11），本函数只适用于 X11。")
    if "DISPLAY" not in os.environ:
        raise RuntimeError("DISPLAY 未设置，无法连接 X 服务器。")
    for cmd in REQUIRED_CMDS:
        if subprocess.run(["which", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
            raise RuntimeError(f"缺少依赖命令：{cmd}")

def _run(cmd: List[str], timeout: Optional[float] = None, check: bool = False, text: bool = True) -> subprocess.CompletedProcess:
    # print("RUN:", " ".join(map(shlex.quote, cmd)))
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=check, text=text)

def _parse_xprop_kv(output: str) -> Dict[str, Optional[str]]:
    """
    解析 xprop 输出为 {prop_name: right_side_string or None}
    - 若属性不存在，值为 None。
    - 若存在，值为 "..." 号后等号右侧的原始字符串（不去掉引号/逗号，只做基本清理）。
    """
    res: Dict[str, Optional[str]] = {}
    for line in output.splitlines():
        if not line.strip():
            continue
        if ":  not found." in line:
            key = line.split(":")[0].strip()
            res[key] = None
            continue
        if " = " in line:
            left, right = line.split(" = ", 1)
            key = left.split("(")[0].strip()
            res[key] = right.strip()
        else:
            # 某些输出没有等号，比如 WM_STATE(window state)
            # 但我们此处只关心上面列举的若干属性，因此忽略其他形式
            pass
    return res

def _get_prop_values_atoms(s: Optional[str]) -> List[str]:
    # 从 '_NET_WM_WINDOW_TYPE(ATOM) = _NET_WM_WINDOW_TYPE_DESKTOP, _NET_WM_WINDOW_TYPE_XXX' 中取出 atom 列表
    if not s:
        return []
    return [v.strip() for v in s.split(",")]

def _get_prop_values_strings(s: Optional[str]) -> List[str]:
    # 从 WM_CLASS(STRING) = "dde-shell", "org.deepin.dde-shell" 中取出字符串列表
    if not s:
        return []
    return [x.strip().strip('"') for x in s.split(",")]

def _get_prop_value_int(s: Optional[str]) -> Optional[int]:
    if not s:
        return None
    m = re.search(r"(-?\d+)", s)
    return int(m.group(1)) if m else None

def _xprop_get(id_hex: str, props: List[str]) -> Dict[str, Optional[str]]:
    cmd = ["xprop", "-notype", "-id", id_hex] + props
    cp = _run(cmd)
    if cp.returncode != 0:
        raise RuntimeError(f"xprop 查询失败: {' '.join(cmd)}\n{cp.stderr}")
    return _parse_xprop_kv(cp.stdout)

def _xprop_set_atoms(id_hex: str, prop: str, atoms: List[str]):
    if not atoms:
        # 移除属性
        _run(["xprop", "-id", id_hex, "-remove", prop])
        return
    value = ", ".join(atoms)
    _run(["xprop", "-id", id_hex, "-f", prop, "32a", "-set", prop, value])

def _xprop_set_cardinal(id_hex: str, prop: str, value: Optional[int]):
    if value is None:
        _run(["xprop", "-id", id_hex, "-remove", prop])
    else:
        _run(["xprop", "-id", id_hex, "-f", prop, "32c", "-set", prop, str(value)])

def _xprop_set_cardinal_list(id_hex: str, prop: str, value_list_str: Optional[str]):
    """
    设置 CARDINAL 数组型（比如 _NET_WM_OPAQUE_REGION）
    value_list_str 形如: '0, 0, 1920, 1080'；如果 None 则移除属性。
    """
    if value_list_str is None:
        _run(["xprop", "-id", id_hex, "-remove", prop])
    else:
        _run(["xprop", "-id", id_hex, "-f", prop, "32c", "-set", prop, value_list_str])

def _wmctrl_states_add(id_hex: str, states: List[str]):
    if not states:
        return
    _run(["wmctrl", "-i", "-r", id_hex, "-b", "add," + ",".join(states)])

def _wmctrl_states_remove(id_hex: str, states: List[str]):
    if not states:
        return
    _run(["wmctrl", "-i", "-r", id_hex, "-b", "remove," + ",".join(states)])

def _get_all_root_child_windows() -> List[str]:
    """
    从 xwininfo -root -tree 中解析所有窗口 id（十六进制 0x...）
    """
    cp = _run(["xwininfo", "-root", "-tree"])
    if cp.returncode != 0:
        raise RuntimeError(f"xwininfo 调用失败: {cp.stderr}")
    ids = re.findall(r"(0x[0-9a-fA-F]+)", cp.stdout)
    # 去重保持顺序
    seen = set()
    out = []
    for wid in ids:
        if wid not in seen:
            seen.add(wid)
            out.append(wid)
    return out

def _get_client_list_ids() -> List[str]:
    cp = _run(["xprop", "-root", "_NET_CLIENT_LIST"])
    if cp.returncode != 0:
        return []
    m = re.search(r"#\s*(.*)$", cp.stdout)
    if not m:
        return []
    ids = re.findall(r"(0x[0-9a-fA-F]+)", m.group(1))
    return ids

def _find_deepin_desktop_window_id() -> str:
    # 先尝试从 _NET_CLIENT_LIST 里找
    ids = _get_client_list_ids()
    candidates = ids if ids else _get_all_root_child_windows()

    for wid in candidates:
        try:
            kv = _xprop_get(wid, ["WM_CLASS", "_NET_WM_WINDOW_TYPE"])
        except Exception:
            continue
        wm_class = _get_prop_values_strings(kv.get("WM_CLASS"))
        wtypes = _get_prop_values_atoms(kv.get("_NET_WM_WINDOW_TYPE"))
        if (DDE_DESKTOP_WM_CLASS_1 in wm_class or DDE_DESKTOP_WM_CLASS_2 in wm_class) and \
           any(t.strip() == "_NET_WM_WINDOW_TYPE_DESKTOP" for t in wtypes):
            return wid

    # 再全量遍历 root->tree 尝试一次
    for wid in _get_all_root_child_windows():
        try:
            kv = _xprop_get(wid, ["WM_CLASS", "_NET_WM_WINDOW_TYPE"])
        except Exception:
            continue
        wm_class = _get_prop_values_strings(kv.get("WM_CLASS"))
        wtypes = _get_prop_values_atoms(kv.get("_NET_WM_WINDOW_TYPE"))
        if (DDE_DESKTOP_WM_CLASS_1 in wm_class or DDE_DESKTOP_WM_CLASS_2 in wm_class) and \
           any(t.strip() == "_NET_WM_WINDOW_TYPE_DESKTOP" for t in wtypes):
            return wid

    raise RuntimeError("未能找到 Deepin 桌面窗口（dde-shell + _NET_WM_WINDOW_TYPE_DESKTOP）。")

def _get_windows_by_pid(pid: int) -> List[str]:
    """
    先用 wmctrl -lp 直接按 PID 过滤；若失败，回退到 _NET_CLIENT_LIST + _NET_WM_PID。
    只返回顶层窗口 id（0x...）。
    """
    wids: List[str] = []
    cp = _run(["wmctrl", "-lp"])
    if cp.returncode == 0:
        for line in cp.stdout.splitlines():
            # 例: 0x03a00007  0  12345  hostname  Window Title...
            parts = line.split(None, 4)
            if len(parts) >= 3:
                wid, _, pid_str = parts[0], parts[2], parts[2]
                try:
                    if int(pid_str) == pid:
                        wids.append(wid)
                except ValueError:
                    pass

    if wids:
        return wids

    # 回退方案：从 _NET_CLIENT_LIST 中逐个取 _NET_WM_PID
    ids = _get_client_list_ids()
    for wid in ids:
        try:
            kv = _xprop_get(wid, ["_NET_WM_PID"])
        except Exception:
            continue
        v = _get_prop_value_int(kv.get("_NET_WM_PID"))
        if v == pid:
            wids.append(wid)

    return wids

def _choose_mpv_main_window(candidates: List[str]) -> Optional[str]:
    """
    从候选窗口里挑出 mpv 主窗口：判断 WM_CLASS 包含 'mpv'
    """
    for wid in candidates:
        try:
            kv = _xprop_get(wid, ["WM_CLASS"])
            wm_class = _get_prop_values_strings(kv.get("WM_CLASS"))
            if any(c.lower() == "mpv" for c in wm_class):
                return wid
        except Exception:
            continue
    # 如果没找到 class=mpv，就返回第一个顶层窗口试试
    return candidates[0] if candidates else None

def _read_window_props(wid: str) -> WindowProps:
    kv = _xprop_get(wid, [
        "_NET_WM_WINDOW_TYPE",
        "_NET_WM_STATE",
        "_NET_WM_WINDOW_OPACITY",
        "_NET_WM_OPAQUE_REGION",
        "WM_CLASS",
    ])
    wtypes = _get_prop_values_atoms(kv.get("_NET_WM_WINDOW_TYPE"))
    states = set(_get_prop_values_atoms(kv.get("_NET_WM_STATE")))
    opacity = _get_prop_value_int(kv.get("_NET_WM_WINDOW_OPACITY"))
    opaque_region = kv.get("_NET_WM_OPAQUE_REGION")
    geom = None
    try:
        geom = _get_window_geometry(wid)
    except Exception:
        pass

    return WindowProps(
        window_type=wtypes if wtypes else None,
        wm_state=states if states else set(),
        opacity=opacity,
        opaque_region=opaque_region,
        geometry=geom,
    )

def _apply_desktop_tweaks(desktop_id: str):
    global ORIGINAL_DESKTOP_PROPS
    if ORIGINAL_DESKTOP_PROPS is None:
        ORIGINAL_DESKTOP_PROPS = _read_window_props(desktop_id)

    # 1) 改类型：DESKTOP -> NORMAL
    _xprop_set_atoms(desktop_id, "_NET_WM_WINDOW_TYPE", ["_NET_WM_WINDOW_TYPE_NORMAL"])

    # 2) 去掉不透明区域
    _run(["xprop", "-id", desktop_id, "-remove", "_NET_WM_OPAQUE_REGION"])

    # 3) 设置特定透明度，触发合成器 ARGB 混合
    _xprop_set_cardinal(desktop_id, "_NET_WM_WINDOW_OPACITY", OPACITY_MAGIC)

    # 4) 去除 above，添加 below/sticky/skip_taskbar/skip_pager
    _wmctrl_states_remove(desktop_id, ["above"])
    _wmctrl_states_add(desktop_id, ["below", "sticky", "skip_taskbar", "skip_pager"])

def _apply_mpv_tweaks(mpv_id: str, target_geom: Tuple[int, int, int, int]):
    if mpv_id not in ORIGINAL_MPV_PROPS:
        ORIGINAL_MPV_PROPS[mpv_id] = _read_window_props(mpv_id)

    # 先移动/缩放到桌面同大小（在切 DESKTOP 前做，兼容性更好）
    try:
        _wmctrl_move_resize(mpv_id, *target_geom)
        time.sleep(0.05)  # 给 WM 一个反应时间（可选）
    except Exception:
        pass

    # 设为 DESKTOP
    _xprop_set_atoms(mpv_id, "_NET_WM_WINDOW_TYPE", ["_NET_WM_WINDOW_TYPE_DESKTOP"])

    # 添加 below/sticky/skip_taskbar/skip_pager，并移除 above
    _wmctrl_states_add(mpv_id, ["below", "sticky", "skip_taskbar", "skip_pager"])
    _wmctrl_states_remove(mpv_id, ["above"])

    # 再尝试一次 resize（部分 WM 在类型变化后需要再确认一次）
    try:
        _wmctrl_move_resize(mpv_id, *target_geom)
    except Exception:
        pass

def _restore_desktop(desktop_id: str):
    global ORIGINAL_DESKTOP_PROPS
    if ORIGINAL_DESKTOP_PROPS is None:
        return
    props = ORIGINAL_DESKTOP_PROPS

    # 还原类型
    _xprop_set_atoms(desktop_id, "_NET_WM_WINDOW_TYPE", props.window_type or [])

    # 还原不透明区域
    _xprop_set_cardinal_list(desktop_id, "_NET_WM_OPAQUE_REGION", props.opaque_region)

    # 还原透明度
    if props.opacity is None:
        _run(["xprop", "-id", desktop_id, "-remove", "_NET_WM_WINDOW_OPACITY"])
    else:
        _xprop_set_cardinal(desktop_id, "_NET_WM_WINDOW_OPACITY", props.opacity)

    # 仅还原我们改动的几个 WM_STATE 标志
    current_states = _read_window_props(desktop_id).wm_state or set()
    desired_states = props.wm_state or set()

    # 我们只操作这 5 个 state（避免动到其他状态）
    touch_atoms = set(STATE_FLAGS_WE_TOUCH.keys())
    cur_touch = {s for s in current_states if s in touch_atoms}
    des_touch = {s for s in desired_states if s in touch_atoms}

    to_add = des_touch - cur_touch
    to_remove = cur_touch - des_touch

    # 转换成 wmctrl 的标志名
    add_flags = [STATE_FLAGS_WE_TOUCH[a] for a in to_add]
    remove_flags = [STATE_FLAGS_WE_TOUCH[a] for a in to_remove]

    _wmctrl_states_remove(desktop_id, remove_flags)
    _wmctrl_states_add(desktop_id, add_flags)

def _restore_mpv(mpv_id: str):
    props = ORIGINAL_MPV_PROPS.get(mpv_id)
    if not props:
        return
    try:
        # 还原类型
        _xprop_set_atoms(mpv_id, "_NET_WM_WINDOW_TYPE", props.window_type or [])

        # 还原我们触碰的状态
        current_states = _read_window_props(mpv_id).wm_state or set()
        desired_states = props.wm_state or set()
        touch_atoms = set(STATE_FLAGS_WE_TOUCH.keys())
        cur_touch = {s for s in current_states if s in touch_atoms}
        des_touch = {s for s in desired_states if s in touch_atoms}
        to_add = des_touch - cur_touch
        to_remove = cur_touch - des_touch
        add_flags = [STATE_FLAGS_WE_TOUCH[a] for a in to_add]
        remove_flags = [STATE_FLAGS_WE_TOUCH[a] for a in to_remove]
        _wmctrl_states_remove(mpv_id, remove_flags)
        _wmctrl_states_add(mpv_id, add_flags)

        # 还原几何（若当时能取到）
        if props.geometry:
            _wmctrl_move_resize(mpv_id, *props.geometry)

    except Exception:
        pass

def _install_exit_hook(restore_func):
    global EXIT_HOOK_INSTALLED
    if EXIT_HOOK_INSTALLED:
        return
    EXIT_HOOK_INSTALLED = True

    def _do_restore(*_args):
        try:
            restore_func()
        finally:
            # 确保只执行一次
            pass

    atexit.register(_do_restore)
    signal.signal(signal.SIGINT, lambda s, f: (_do_restore(), os._exit(130)))
    signal.signal(signal.SIGTERM, lambda s, f: (_do_restore(), os._exit(143)))

def set_video_wallpaper_mode(mpv_pid: int, enable: bool = True, wait_for_mpv: float = 10.0) -> Tuple[Optional[str], Optional[str]]:
    """
    一个函数开关：
    - enable=True: 应用层级调整（修改桌面窗口 & mpv 窗口）
    - enable=False: 还原修改
    返回 (desktop_id, mpv_window_id) ，失败时各自为 None。
    """
    global DESKTOP_WIN_ID, APPLIED

    _check_env()

    if enable:
        # 幂等：已经应用过则直接返回
        if APPLIED:
            return (DESKTOP_WIN_ID, next(iter(ORIGINAL_MPV_PROPS.keys()), None))

        # 1) 获取/缓存桌面窗口 id（首次）
        if not DESKTOP_WIN_ID:
            DESKTOP_WIN_ID = _find_deepin_desktop_window_id()

        # 2) 轮询获取 mpv 顶层窗口 id
        mpv_id: Optional[str] = None
        t0 = time.time()
        while time.time() - t0 < wait_for_mpv and not mpv_id:
            cand = _get_windows_by_pid(mpv_pid)
            wid = _choose_mpv_main_window(cand)
            if wid:
                mpv_id = wid
                break
            time.sleep(0.2)

        if not mpv_id:
            raise RuntimeError(f"在 {wait_for_mpv}s 内未找到 mpv(pid={mpv_pid}) 的窗口。")

        # 3) 应用修改
        _apply_desktop_tweaks(DESKTOP_WIN_ID)

        # 取桌面窗口几何
        desk_geom = _get_window_geometry(DESKTOP_WIN_ID)

        # 把 mpv 调整到同样大小，并设置类型/层级
        _apply_mpv_tweaks(mpv_id, desk_geom)

        # 安装退出还原钩子
        _install_exit_hook(lambda: set_video_wallpaper_mode(mpv_pid, enable=False))
        APPLIED = True
        return (DESKTOP_WIN_ID, mpv_id)

    else:
        # 还原（如果有）
        if not APPLIED:
            return (DESKTOP_WIN_ID, next(iter(ORIGINAL_MPV_PROPS.keys()), None))

        # 还原 mpv（可能已退出，容忍失败）
        for mpv_id in list(ORIGINAL_MPV_PROPS.keys()):
            _restore_mpv(mpv_id)
        ORIGINAL_MPV_PROPS.clear()

        # 还原桌面
        if DESKTOP_WIN_ID:
            try:
                _restore_desktop(DESKTOP_WIN_ID)
            except Exception as e:
                print(f"[warn] 还原桌面失败：{e}")

        # 清理状态（保留 DESKTOP_WIN_ID 作为缓存，以便同一次运行中再次启用时使用）
        global ORIGINAL_DESKTOP_PROPS
        ORIGINAL_DESKTOP_PROPS = None
        APPLIED = False
        return (DESKTOP_WIN_ID, None)

# 如果你偏向上下文管理器用法，也可以这样封装：
from contextlib import contextmanager
@contextmanager
def video_wallpaper_stacking(mpv_pid: int, wait_for_mpv: float = 10.0):
    try:
        set_video_wallpaper_mode(mpv_pid, enable=True, wait_for_mpv=wait_for_mpv)
        yield
    finally:
        # 注意：如果 mpv 已经提前退出，这里也会尝试还原（失败容忍）
        set_video_wallpaper_mode(mpv_pid, enable=False)


# --------------切换窗口层级结束---------------------

if __name__ == "__main__":
    # ---------------测试函数----------------------
    # print(check_lock_screen())
    # print(check_blank_screen())
    # print(xprintidle())
    # print(check_no_app_window())

    #sock = "ipc_server"
    # 播放/继续
    #ok, reply = send_mpv_ipc(sock, MPV_CMD_PLAY)
    #print(ok, reply)
    
    #time.sleep(5)

    # 暂停
    #ok, reply = send_mpv_ipc(sock, MPV_CMD_PAUSE)
    #print(ok, reply)

    #time.sleep(5)
    
    # 更换视频
    #cmd = dict(MPV_CMD_LOADFILE)          # 浅拷贝
    #cmd["command"][1] = "LIGHT01_20250623_V3_sdr_4k_rate12000_240p_t2160_grover74_tsa_nclc111.mov"
    #ok, reply = send_mpv_ipc(sock, cmd)
    #print(ok, reply)

    #time.sleep(5)
    
    # 查看整个播放列表
    #ok, reply = send_mpv_ipc(sock, {"command": ["get_property", "playlist"]})
    #print(ok, reply)  # reply["data"] 是一个数组，每个元素里通常有 filename、current、id 等字段

    # 启用（会在进程退出时自动还原）
    # desktop_id, mpv_id = set_video_wallpaper_mode(3375586, enable=True)
    
    # time.sleep(5)

    # ---------------测试函数----------------------
```
