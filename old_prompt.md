我需要你帮我编写一个python脚本，它用于实现“节能的视频壁纸”。
它将控制视频壁纸的产生、播放、暂停，它用一些系统调用来探测当前状态是否符合视频播放的条件，如果符合才会播放，否则保持暂停。
具体来看程序逻辑部分。

# 程序逻辑

这个视频壁纸将在Deepin下运行，使用最常用的mpv + xwinwrap方案。

与常见方案不同的是，它需要实现检测当前系统的状态，还需要按照系统时间将4个视频在不同的时间区间内循环播放，还需要控制mpv的播放与暂停，还需要在可以播放视频的时机，探测系统状态来决定隐藏桌面文件图标的时机，并隐藏桌面文件图标。

想必你已经了解一个大概，下面开始详细描述程序逻辑。

## 何时播放视频？

首先，其他时机需要暂停视频。

只有满足以下条件，才会播放视频：
1. 桌面上没有任何应用程序窗口
2. 屏幕正在显示，屏幕不处于锁屏和熄屏的状态下

## 何时隐藏桌面文件图标？

未满足以下条件时，不隐藏桌面文件图标。

只有满足以下条件，才隐藏桌面文件图标：
1. 已满足视频播放的条件
2. 5秒钟内未移动鼠标和操作键盘

## 脚本需要控制mpv + xwinwrap首次启动吗？

需要！

# 视频文件与循环播放时机
一共有4段视频，每段视频时长几分钟。4个视频文件，其中：
- DARK01_20250703_v10_sdr_4k_rate12000_240p_t2160_grover74_tsa_nclc111.mov，是太阳升起之前的
- LIGHT02_20250613_V2_sdr_4k_rate12000_240p_t2160_grover74_tsa_MTE-Modified.mov，是太阳直射的
- LIGHT01_20250623_V3_sdr_4k_rate12000_240p_t2160_grover74_tsa_nclc111.mov，是太阳落入地平线之前的
- DARK02_20250719_V1_FRC_240fps_sdr_4k_rate12000_240p_t2160_grover74_tsa_nclc111.mov，是夜晚的

第一段视频为太阳升起之前的，在24小时制的05:00:00~07:59:59循环播放。
第二段视频为太阳直射的，在24小时制的08:00:00~16:59:59循环播放。
第三段视频为太阳落入地平线之前的，在24小时制的17:00:00~19:59:59循环播放。
第四段视频为夜晚的，在24小时制的20:00:00~04:59:59循环播放。

# 技术难点与实现方法

## 检测屏幕上没有应用程序窗口
xprop + _NET_WM_STATE_HIDDEN + 排除操作系统窗口 来实现

排除操作系统窗口的方法是：获取 `_NET_WM_WINDOW_TYPE` ，如果里面包含 `_NET_WM_WINDOW_TYPE_DOCK` `_NET_WM_WINDOW_TYPE_DESKTOP` 其中一个，则为操作系统窗口。如果只有 `_NET_WM_WINDOW_TYPE_NORMAL` 则为非操作系统窗口。

## 检测屏幕正在显示，而不是锁屏、熄屏
1. 检测不是锁屏用dbus的org.deepin.dde.LockFront1的Visible(只读属性)

接口文档如下：
```
dbus-send --print-reply --dest=org.deepin.dde.LockFront1     /org/deepin/dde/LockFront1     org.freedesktop.DBus.Introspectable.Introspect
method return time=1755980995.742209 sender=:1.59 -> destination=:1.2928 serial=1976 reply_serial=2
   string "<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.deepin.dde.LockFront1">
    <property name="Visible" type="b" access="read"/>
    <signal name="ChangKey">
      <arg name="key" type="s" direction="out"/>
    </signal>
    <signal name="Visible">
      <arg name="visible" type="b" direction="out"/>
    </signal>
    <method name="Show">
    </method>
    <method name="ShowUserList">
    </method>
    <method name="ShowAuth">
      <arg name="active" type="b" direction="in"/>
    </method>
    <method name="Suspend">
      <arg name="enable" type="b" direction="in"/>
    </method>
    <method name="Hibernate">
      <arg name="enable" type="b" direction="in"/>
    </method>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get">
      <arg name="interface_name" type="s" direction="in"/>
      <arg name="property_name" type="s" direction="in"/>
      <arg name="value" type="v" direction="out"/>
    </method>
    <method name="Set">
      <arg name="interface_name" type="s" direction="in"/>
      <arg name="property_name" type="s" direction="in"/>
      <arg name="value" type="v" direction="in"/>
    </method>
    <method name="GetAll">
      <arg name="interface_name" type="s" direction="in"/>
      <arg name="values" type="a{sv}" direction="out"/>
      <annotation name="org.qtproject.QtDBus.QtTypeName.Out0" value="QVariantMap"/>
    </method>
    <signal name="PropertiesChanged">
      <arg name="interface_name" type="s" direction="out"/>
      <arg name="changed_properties" type="a{sv}" direction="out"/>
      <annotation name="org.qtproject.QtDBus.QtTypeName.Out1" value="QVariantMap"/>
      <arg name="invalidated_properties" type="as" direction="out"/>
    </signal>
  </interface>
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect">
      <arg name="xml_data" type="s" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.DBus.Peer">
    <method name="Ping"/>
    <method name="GetMachineId">
      <arg name="machine_uuid" type="s" direction="out"/>
    </method>
  </interface>
</node>
"
```

你可以`import dbus`来操作dbus。

2. 检测不是熄屏（黑屏）用xset命令

## 让桌面不显示图标

用xprop拿到`_NET_CLIENT_LIST_STACKING(WINDOW)`，并找出`_NET_WM_WINDOW_TYPE`里面有`_NET_WM_WINDOW_TYPE_DESKTOP`的窗口id，然后执行`xdotool windowunmap 窗口id`
若要恢复，可使用`xdotool windowmap 窗口id`

## 控制 mpv + xwinwrap 播放、暂停、更换视频

mpv + --input-ipc-server + socket

--input-ipc-server可以让mpv给出一个socket，可以往这个socket中写入用于控制mpv的json。

它可以实现：
- 播放
- 暂停
- 替换视频

你可以使用Python的`import socket`。

## 如何检测5秒内未按下键盘或者移动鼠标？

我提供给你一个脚本`xprintidle.py`，这个脚本我已经编写完成了，你只需使用`python3 xprintidle.py`调用它，这个脚本会打印数字，单位是毫秒，这个数字是指：当前时间，距离上一次操作键盘和鼠标的持续时间。有时也称为“用户空闲时间”、“无操作时间”。

---

检查命令是否存在
for c in xwininfo xrandr wmctrl xprop xdotool awk sed grep ps; do need_cmd "$c"; done

还是得用wmctrl

---

我想请你帮我完成一个python函数，这个函数并不算简单，为了实现这个函数，我有必要告诉你一些背景信息。

我在做一个稍微有些复杂的东西，我要在deepin上实现视频壁纸。为了实现视频壁纸，我正在开发一个python脚本，这个脚本负责启动 `mpv` 并与之通信，它还通过一些系统调用与x11窗口、锁屏、熄屏等系统功能通信。这个脚本最终的目的是实现一个基于策略的节能视频壁纸。

回到python函数，我要用一个python函数来进行一系列操作，这些操作的目的是为了修复Deepin DDE桌面实现的一些问题。

DDE的桌面壁纸和桌面图标处在同一个窗口，有些linux桌面壁纸和图标处在两个窗口，也就是分开的，如果是分开的，则实现视频壁纸的话，可以在壁纸和图标的窗口之间添加一个窗口，这个窗口在壁纸之上，图标之下，图标就可以呈现在视频壁纸（这个窗口）之上。

但由于**Deepin的桌面壁纸和桌面图标是一个窗口**，就没办法用我上面说的那种方案。

我经过测试和研究，找到了一个可行的方案。我将描述这个方案。

我们需要这么几步：
1. 手动通过Deepin的控制中心（设置）的GUI界面，修改视频壁纸为.png的全透明图片。
2. DDE的桌面和图标是一个窗口，我们把它称为桌面。修改桌面窗口的属性和层级。
3. 启动 `mpv` 并修改mpv窗口的属性和层级，从而将mpv放在桌面窗口下面。

我解释一下：
这个步骤是我测试过的可行实现，但在函数中不完全按照这个步骤做，因为一些操作在函数外面进行。（我会在后面说函数里面做什么）
第一步如果没有，看上去的效果就会是：图片壁纸覆盖了视频壁纸。
第二步会让合成器以aplha形式混合桌面窗口，从而让底下的窗口穿透桌面窗口中透明的部分显示出来，还会修改桌面窗口类型和层级。
第三步就显而易见了，启动并修改mpv的窗口类型和层级，将mpv放在桌面窗口下面。

第二步的实现：
```
寻找桌面id：
WM_CLASS(STRING) = "dde-shell", "org.deepin.dde-shell"
_NET_WM_WINDOW_TYPE(ATOM) 包含 _NET_WM_WINDOW_TYPE_DESKTOP

修改桌面窗口的类型为正常：
xprop -id "$ICON" -f _NET_WM_WINDOW_TYPE 32a -set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_NORMAL

去除“用来告诉合成器这个窗口里哪些矩形区域是完全不透明的”属性
xprop -id $ICON -remove _NET_WM_OPAQUE_REGION

设置一个透明度，目的是让合成器以alpha(argb)形式混合，从而让.png透明壁纸呈现透明状态
4252017622 这个值是特定的，DDE默认 _NET_WM_WINDOW_OPACITY 是这个值，只有它有效。重新设置这个值会让合成器以alpha(argb)形式混合
xprop -id 0x03600007 -f _NET_WM_WINDOW_OPACITY 32c -set _NET_WM_WINDOW_OPACITY 4252017622

去除桌面的above属性
wmctrl -i -r "$ICON" -b remove,above

给桌面添加属性，below、在所有虚拟桌面中显示、不在任务栏、分页器中显示
wmctrl -i -r "$ICON" -b add,below,sticky,skip_taskbar,skip_pager
```

第三步除了启动mpv的实现：
```
设为 DESKTOP 层并置底、隐藏任务栏/分页器
xprop -id "$id" -f _NET_WM_WINDOW_TYPE 32a -set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_DESKTOP
添加属性，below、在所有虚拟桌面中显示、不在任务栏、分页器中显示
wmctrl -i -r "$id" -b add,below,sticky,skip_taskbar,skip_pager
```

回到需要写的函数，这个函数做什么？

它在我的脚本中用来实现**调整窗口层级**，它不需要启动mpv，但是它除了把mpv放在桌面窗口下面，它还要实现将mpv放在桌面窗口上面。

为什么呢？因为桌面图标会挡住看视频壁纸的体验，所以我设计了一套逻辑，在某个时机会让桌面图标消失。如何消失呢？将mpv放在桌面窗口上面则是一个不错的选择。

这个函数的入参中会有一个参数来表示状态，是桌面在下，mpv在上，还是反过来。

我会将mpv的pid传入函数，函数需要根据pid用linux命令查询到窗口id，然后修改属性和层级等。

桌面的窗口id由函数自己获取。

对于寻找桌面窗口id的逻辑，你会发现在“切换”功能实现的时候，当切换mpv为上层的时候，此时_NET_WM_WINDOW_TYPE_DESKTOP并不在桌面窗口上，是的。
但是如果你只通过WM_CLASS(STRING) = "dde-shell", "org.deepin.dde-shell"来判断，你会发现有若干符合条件的。即使你通过窗口大小之类的分析，仍有几个符合条件的，这样就无法确定哪个是桌面窗口。

所以我有一个好主意，我们可以把脚本设计为幂等的，你可以在全局存一个桌面窗口的id作为变量，当函数被调用时，函数去读取这个变量，如果为空则桌面窗口一定处在没有任何改变的状态，此时获取桌面窗口的id并赋值变量。如果不为空，我们变量中已经有桌面窗口id了也就不需要获取了。
设置好hook，在脚本因任何原因结束时，将一切恢复。

你可以将hook的函数放在外面，hook函数里面调用窗口层级切换的`_xxx`函数，也就是俩暴露出来的函数了，一个用于窗口层级切换，一个用于执行hook的逻辑。
这样我就可以在hook的函数里面添加其他逻辑，这样就成为一个全局的hook了。

注意：
1、不要去除mpv窗口的_NET_WM_STATE_FULLSCREEN以避免退出全屏。
2、xdotool只有windowraise无windowlower。
3、希望使用xlib实现修改层级后立即重排堆叠顺序。
