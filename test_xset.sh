#!/bin/bash

while true; do
    # 获取当前时间戳
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 使用xset查询显示器状态
    result=$(xset q 2>/dev/null | grep -o "Monitor is Off\|Monitor is On")
    
    # 检查命令执行结果
    if [ $? -ne 0 ]; then
        echo "[$timestamp] 错误: 无法获取屏幕状态（请检查X服务器是否运行）"
    else
        case $result in
            "Monitor is On")
                echo "[$timestamp] 屏幕状态: 亮屏"
                ;;
            "Monitor is Off")
                echo "[$timestamp] 屏幕状态: 熄屏"
                ;;
            *)
                echo "[$timestamp] 未知状态: $result"
                ;;
        esac
    fi
    
    # 等待60秒
    sleep 60
done
