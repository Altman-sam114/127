# Tiled 开源代码研究与借鉴报告 (v0.34)

基于对 `MapEditor/tiled-master` 源码的深入阅读，我为你提取了 Tiled 中与本项目（二战六角格战略游戏）最相关的核心架构和设计哲学，并评估了哪些内容可以直接移植或借鉴到我们即将开发的 iOS/Mac 最小化地图编辑器中。

## 1. 源码架构概览
Tiled 使用 C++ 和 Qt 框架开发，其核心分为两大块：
*   **`src/tiled/`**: 用户界面（UI）、工具箱、画笔工具的交互逻辑。
*   **`src/libtiled/`**: 核心数据模型层。这部分完全独立于 UI，包含 `Map`, `Layer`, `Tile`, `Hex`, `Properties` 等定义，以及渲染器接口。

> **结论**：我们无法直接复制 C++ 代码到现有的 Swift / SpriteKit 工程中，但 `libtiled` 里的**数学算法和数据结构设计**极具借鉴价值，甚至可以直接被无缝翻译成 Swift。

---

## 2. 坐标系统与六角网格数学 (最核心借鉴)
深入研究 `libtiled/hex.h` 和 `libtiled/hex.cpp` 后，我发现 Tiled 对六角网格（Hexagonal Grid）的处理非常经典，完全符合业界权威（Amit Patel / Red Blob Games）的标准：

*   **Cube Coordinates (立方体坐标 xy z)**：Tiled 内部的 `Hex` 类没有使用 `(q, r)`（这也是为什么简单的二维数组处理 hex 容易出错的原因），它直接使用了 `x, y, z` 三轴坐标系统来表示一个 Hex（保证 `x + y + z = 0`）。
*   **Staggered 转换**：底层存储依然是通过 `toStaggered(staggerIndex, staggerAxis)` 转换回常规的二维坐标以便存入数组。

### 借鉴动作：
1. 我们现有的 `HexCoord.swift` 只有 `(q, r)`，这在做**战区划线、计算邻居（邻接关系）和六边形包围判定**时异常痛苦。
2. 我们应立刻将 Tiled 的 `Hex(x, y, z)` 和相应的加减运算 `+`, `-` 以及绕原点 `rotate()` 等纯数学逻辑，**逐行翻译成 Swift 添加到我们的 `HexCoord` 中**。这将大幅度简化 v0.34 需要做的“自动拓扑边缘检测”。
3. **拾取算法（Hit Testing）**: Tiled 在 `hexagonalrenderer.cpp` 里面有极其成熟的“鼠标像素坐标转 Hex 坐标”的纯数学检测，我们可以直接搬运这个算法到 `SpriteKit` 的点击事件中，确保完全精准的点选。

---

## 3. 数据隔离与解耦哲学 (图层机制)
Tiled 之所以好扩展，全都归功于 `libtiled/layer.h` 以及其子类的设计：
*   **`TileLayer`（瓦片层）**: 用严格的二维数组存储连续网格，只用来刷“地形底图”（平原、森林、山地等）。
*   **`ObjectGroup`（对象层）**: 这是一张完全脱离网格的大画布，用于记录带明确绝对坐标的独立对象（点），可以跨越格子！

### 借鉴动作：
我们的数据结构已经隐隐约约有了这个模式。在后续自己做编辑器时也要严格遵守这样的渲染与存储隔离：
1. **地形是网格**：森林、平原存到类似 `TileLayer` 的二阶数组里。
2. **部队、城市、补给站应设计成 `Object`**：不要把这些东西挂在 `HexTile` 的强类型属性下，而是作为一个独立对象（仅具有 `hex_q`, `hex_r` 或者 `regionId` 属性）。

---

## 4. 万物皆可挂属性 (Properties 机制)
查看 `libtiled/properties.h`，这是 Tiled 最迷人的地方。
在 Tiled 中，不管是 `Map`, `Layer`, `Tile` 还是 `Object`，全都继承了一个共同特征：**允许挂载无限数量的用户自定义键值对（`Properties ` 字典）**。
它是 `QString -> QVariant`（任意类型）的哈希表。

### 借鉴动作：
在后续设计项目拓展能力（天气、补给、不可通行区域、甚至政治干预点）时，我们应该：
1. 给现有的 `RegionNode` 或者未来的地图格加入一个 `var metadata: [String: String]` 的字典。
2. 编辑器不必为了一个“暴风雪天气”专门重新开发界面版块，只需要向字典里 push 一个 `["weather": "snowstorm"]`，然后在游戏内的事件引擎使用 `if metadata["weather"] == "snowstorm"` 来结算惩罚。这就是高扩展性的终极解法。

---

## 5. 总结：什么可以直接“抄”？

在开发 v0.34 的 iOS/macOS 内置地图编辑器时，**你应该让 Codex 去阅读这些 C++ 文件，并翻译以下模块为 Swift**：

1. **翻译** `src/libtiled/hex.cpp` -> 强化现有的 `HexCoord` 结构，提供极其方便的六维寻路和边获取。
2. **翻译** `src/libtiled/hexagonalrenderer.cpp` 中的 `pixelToMapLocation` 与 `tileRect` -> 用于你的编辑器完美捕捉鼠标焦点和绘制描边。
3. **架构借鉴** `src/libtiled/map.h` 的图层管理模式 -> 将地图结构梳理为 `[TerrainLayer (1个网格), RegionLayer (1层画笔区域), ObjectsLayer (城市点位)]`。

抛弃笨重的通用 C++ 界面与转换脚本，把这些久经考验的核心底核算法抽出，你的自建编辑器将同时拥有 Tiled 的精准和专属的无缝接入体验。
