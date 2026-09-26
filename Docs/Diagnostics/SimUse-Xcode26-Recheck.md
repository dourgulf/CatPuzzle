# sim-use 回退 Xcode 后复测

日期：2026-09-26。仅检查工具和实际交互，未修改游戏逻辑。

## 环境

- Xcode 26.6，build 17F113
- Developer Directory：`/Applications/Xcode.app/Contents/Developer`
- sim-use 0.14.0
- iPhone 16，iOS 26.5
- Simulator UDID：`F4873577-EC1A-4C2E-9E97-759A3FACF67B`

## 实际验证

| 操作 | 观察结果 |
| --- | --- |
| preflight、读取 UI | 通过，能读取 393×852 画面和棋盘格状态 |
| 点击设置页 Done | 设置页关闭；页面切换后读取到教程入口 |
| 点击 Start Tutorial | 进入初始教程棋盘 |
| 单击粉色格 cell-2-1 | 格子仍为空，出现 Double-tap this cell to place a cat. |
| 间隔 0.1 秒双击粉色格 | 格子变 Cat，首张规则卡出现，进入行标记教学 |
| 点击第 3 行其余 5 格 | 全部变 Excluded，进入列标记教学 |
| 从 (109,254) 向下滑至 (109,545)，持续 1.4 秒 | 第 2 列其余 5 格全部变 Excluded，已有猫保留，第二张规则卡出现，进入邻格教学 |
| 截图 | 正常保存拖拽后的棋盘 |

本次点击、双击和拖拽均通过实际棋盘变化验证，未重现此前“命令成功但画面不变”的情况。

## 仍需注意的现象

1. 关闭设置后的一次即时读取提示前台 accessibility tree 为空，使用其他进程恢复了部分元素；下一次读取恢复完整层级。此时处于页面切换阶段，不能据此认定稳定页面仍有层级故障。
2. 首次读取棋盘后，下一次点击 open-settings 时该元素已不存在，最新画面已是设置页。这次返回明确 no-match，而非虚假的成功；两次观察之间页面已变化，原因未确认。
3. 用户提供了 sim-use 主页关于 Xcode 27 问题的信息；本次独立确认的是 Xcode 26 环境下上述交互正常，未独立验证主页内容或确定此前故障的唯一根因。

## 复现命令与本机临时证据

```bash
sim-use ui --device F4873577-EC1A-4C2E-9E97-759A3FACF67B
sim-use ios batch --device F4873577-EC1A-4C2E-9E97-759A3FACF67B \
  --step 'tap --point 109,370' --step 'sleep 0.1' \
  --step 'tap --point 109,370' --step 'sleep 0.5'
sim-use swipe --from 109,254 --to 109,545 --duration 1.4 \
  --device F4873577-EC1A-4C2E-9E97-759A3FACF67B --post-delay 0.5
```

坐标仅适用于本次最新层级确认的棋盘，重试应先读取当前界面。

临时证据：`/tmp/cat-xcode26-single.txt`、`/tmp/cat-xcode26-double.txt`、
`/tmp/cat-xcode26-row.txt`、`/tmp/cat-xcode26-drag.txt`、`/tmp/cat-xcode26-drag.png`。

验证范围止于首列拖拽完成；未把本次工具复测作为整关流程、循环动画或所有设备的全面验收。
